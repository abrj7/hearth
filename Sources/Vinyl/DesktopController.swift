import AppKit
import SceneKit
import ServiceManagement

/// User-facing state shared by the desktop scene, the menu and the settings window.
final class AppState: ObservableObject {
    static let sizeFactors: [CGFloat] = [1.2, 1.0, 0.84]
    static let sizeNames = ["Small", "Medium", "Large"]
    private let defaults = UserDefaults.standard

    @Published var track: Track?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var thumbnails: [NSImage] = []
    @Published var preset: TurntableScene.Preset { didSet { defaults.set(preset.rawValue, forKey: "preset"); onChange?() } }
    @Published var sizeIndex: Int { didSet { defaults.set(sizeIndex, forKey: "size"); onChange?() } }
    @Published var transparent: Bool { didSet { defaults.set(transparent, forKey: "transparent"); onChange?() } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Vinyl: launch at login failed: \(error.localizedDescription)")
            }
        }
    }
    var onChange: (() -> Void)?

    init() {
        preset = TurntableScene.Preset(rawValue: defaults.integer(forKey: "preset")) ?? .daylight
        sizeIndex = defaults.object(forKey: "size") as? Int ?? 1
        transparent = defaults.bool(forKey: "transparent")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Owns the wallpaper-level window and turns desktop clicks into turntable clicks.
final class DesktopController: NSObject, SCNSceneRendererDelegate {
    let scene: TurntableScene
    private let state: AppState
    private let window: NSWindow
    private let view: SCNView
    private var keepAliveUntil: CFTimeInterval = 0
    private var mouseDownAt: NSPoint?
    private var appliedPreset: TurntableScene.Preset
    private var appliedSize: Int
    private var appliedTransparent = false
    var onTurntableClick: (() -> Void)?

    init(state: AppState) {
        self.state = state
        scene = TurntableScene()
        for seed in [3, 4] as [UInt64] { scene.pushToStack(Tex.placeholderCover(seed: seed), animated: false) }
        appliedPreset = state.preset
        appliedSize = state.sizeIndex

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        view = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        super.init()

        // Just above the system wallpaper, below desktop icons and every normal window.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        view.scene = scene.scene
        view.pointOfView = scene.cameraNode
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.autoresizingMask = [.width, .height]
        view.delegate = self
        window.contentView = view

        scene.setSize(AppState.sizeFactors[state.sizeIndex], animated: false)
        scene.apply(preset: state.preset, animated: false)
        applyTransparency(state.transparent)
        window.orderFrontRegardless()
        kick(3)

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleGlobalMouse(event)
        }
    }

    @objc private func screensChanged() {
        if let frame = NSScreen.main?.frame { window.setFrame(frame, display: true) }
        kick(2)
    }

    // MARK: Rendering

    /// Render continuously for a while; the delegate stops the loop once everything is still.
    func kick(_ seconds: CFTimeInterval = 4) {
        keepAliveUntil = max(keepAliveUntil, CACurrentMediaTime() + seconds)
        view.isPlaying = true
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let now = CACurrentMediaTime()
        let moving = scene.update(at: now)
        if !moving && now > keepAliveUntil {
            DispatchQueue.main.async { [weak self] in
                guard let self, CACurrentMediaTime() > self.keepAliveUntil, !self.state.isPlaying else { return }
                self.view.isPlaying = false
            }
        }
    }

    /// Debug aid: `kill -USR1 <pid>` writes what the desktop currently shows to the caches folder.
    func writeLiveSnapshot() {
        let image = view.snapshot()
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("com.abrj7.vinyl") else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writePNG(cg, to: dir.appendingPathComponent("live.png").path)
        let t = state.track
        try? "\(state.isPlaying ? "playing" : "paused") | \(t?.title ?? "-") | \(t?.artist ?? "-") | \(t?.player.displayName ?? "-")\n"
            .write(to: dir.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: State changes

    func setPlaying(_ playing: Bool) {
        scene.setPlaying(playing, animated: true)
        kick(playing ? 4 : 8)
    }

    func setArtwork(_ art: CGImage) {
        scene.setArtwork(art, pushPrevious: true, animated: true)
        kick(4)
    }

    func applySettings() {
        if state.transparent != appliedTransparent { applyTransparency(state.transparent) }
        if state.sizeIndex != appliedSize {
            appliedSize = state.sizeIndex
            scene.setSize(AppState.sizeFactors[state.sizeIndex], animated: true)
        }
        if state.preset != appliedPreset {
            appliedPreset = state.preset
            scene.apply(preset: state.preset, animated: true)
        }
        kick(4)
    }

    private func applyTransparency(_ on: Bool) {
        appliedTransparent = on
        scene.setTransparent(on)
        window.isOpaque = !on
        window.backgroundColor = on ? .clear : .black
        view.backgroundColor = on ? .clear : .black
    }

    // MARK: Clicks

    private func handleGlobalMouse(_ event: NSEvent) {
        let p = NSEvent.mouseLocation
        if event.type == .leftMouseDown {
            mouseDownAt = p
            return
        }
        guard let down = mouseDownAt, hypot(p.x - down.x, p.y - down.y) < 5 else { return }
        mouseDownAt = nil
        guard window.frame.contains(p), isDesktopExposed(at: p) else { return }
        let local = view.convert(window.convertPoint(fromScreen: p), from: nil)
        let hits = view.hitTest(local, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        if TurntableScene.isTurntable(hits.first?.node) { onTurntableClick?() }
    }

    /// True when no ordinary window covers this screen point, i.e. the click landed on the desktop.
    private func isDesktopExposed(at p: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }), screen.visibleFrame.contains(p),
              let primary = NSScreen.screens.first else { return false }
        let cgPoint = CGPoint(x: p.x, y: primary.frame.height - p.y)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return true }
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, (0...8).contains(layer),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if bounds.contains(cgPoint) { return false }
        }
        return true
    }
}
