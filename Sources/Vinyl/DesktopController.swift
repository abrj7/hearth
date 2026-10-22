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
