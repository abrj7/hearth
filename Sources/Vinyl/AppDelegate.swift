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
        desktop.onTurntableClick = { [weak self] in self?.monitor.togglePlayPause() }
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
