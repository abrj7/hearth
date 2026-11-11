import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = AppState()
    private let monitor = NowPlayingMonitor()
    private var desktop: DesktopController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var currentKey: String?
    private var thumbnailWork: DispatchWorkItem?
    private var debugSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        desktop = DesktopController(state: state)
        desktop.onControl = { [weak self] control in
            switch control {
            case .playPause: self?.monitor.togglePlayPause()
            case .next: self?.monitor.skip(forward: true)
            case .previous: self?.monitor.skip(forward: false)
            }
        }
        state.onChange = { [weak self] in
            DispatchQueue.main.async { self?.desktop.applySettings() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "opticaldisc.fill", accessibilityDescription: "Vinyl")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        signal(SIGUSR1, SIG_IGN)
        debugSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        debugSignal?.setEventHandler { [weak self] in self?.desktop.writeLiveSnapshot() }
        debugSignal?.resume()

        monitor.onChange = { [weak self] track, playing in self?.playbackChanged(track, playing) }
        monitor.start()
        // Re-check the clock after sleep, so the scene is right the moment the Mac wakes.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.state.syncSceneToClock()
        }
        refreshThumbnails()

        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Playback

    private func playbackChanged(_ track: Track?, _ playing: Bool) {
        NSLog("Vinyl: %@ — %@ (%@)", playing ? "playing" : "paused", track?.title ?? "nothing", track?.player.displayName ?? "-")
        state.track = track
        state.isPlaying = playing
        desktop.setPlaying(playing)

        guard let track, track.key != currentKey else { return }
        currentKey = track.key
        Artwork.fetch(for: track) { [weak self] image in
            guard let self, self.currentKey == track.key else { return }
            NSLog("Vinyl: cover %@ for %@", image == nil ? "not found" : "loaded", track.album)
            let seed = UInt64(track.album.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF })
            let cover = image.flatMap { Tex.square($0) } ?? Tex.placeholderCover(seed: seed)
            self.state.artwork = NSImage(cgImage: cover, size: NSSize(width: 512, height: 512))
            self.desktop.setArtwork(cover)
            self.refreshThumbnails()
        }
    }

    /// Re-render the three scene previews with the current cover (off the main thread).
    private func refreshThumbnails() {
        thumbnailWork?.cancel()
        let art = desktop.scene.currentArt
        let work = DispatchWorkItem { [weak self] in
            let stack = (1...3).map { Tex.placeholderCover(seed: UInt64($0)) }
            let images = TurntableScene.Preset.allCases.map {
                renderStill(preset: $0, size: CGSize(width: 480, height: 300), art: art, stack: stack, playing: true)
            }
            DispatchQueue.main.async { self?.state.thumbnails = images }
        }
        thumbnailWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let t = state.track {
            let title = NSMenuItem(title: t.title, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            let sub = NSMenuItem(title: "\(t.artist) · \(t.player.displayName)", action: nil, keyEquivalent: "")
            sub.isEnabled = false
            menu.addItem(sub)
            menu.addItem(item(state.isPlaying ? "Pause" : "Play", #selector(togglePlayback)))
            menu.addItem(item("Next", #selector(nextTrack)))
            menu.addItem(item("Previous", #selector(previousTrack)))
        } else {
            let idle = NSMenuItem(title: "Play something in Spotify or Apple Music", action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.addItem(idle)
        }
        menu.addItem(.separator())
        for p in TurntableScene.Preset.allCases {
            let i = item(p.title, #selector(pickScene(_:)))
            i.tag = p.rawValue
            i.state = state.preset == p ? .on : .off
            menu.addItem(i)
        }
        let auto = item("Match Time of Day", #selector(toggleAuto))
        auto.state = state.autoScene ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Quit Vinyl", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func togglePlayback() { monitor.togglePlayPause() }
    @objc private func nextTrack() { monitor.skip(forward: true) }
    @objc private func previousTrack() { monitor.skip(forward: false) }
    @objc private func pickScene(_ sender: NSMenuItem) {
        if let p = TurntableScene.Preset(rawValue: sender.tag) { state.pick(p) }
    }
    @objc private func toggleAuto() { state.autoScene.toggle()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(srgbRed: 0.075, green: 0.07, blue: 0.068, alpha: 1)
            w.contentViewController = NSHostingController(rootView: SettingsView(state: state, togglePlayback: { [weak self] in
                self?.monitor.togglePlayPause()
            }))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
