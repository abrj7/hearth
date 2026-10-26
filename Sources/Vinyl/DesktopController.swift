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

