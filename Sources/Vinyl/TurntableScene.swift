import AppKit
import SceneKit

/// The whole desk: room, turntable, sleeve, record stack, lamp and lights.
/// Units are decimetres (a 12" record has radius 1.5).
final class TurntableScene {
    enum Preset: Int, CaseIterable, Identifiable {
        case daylight, lamplight, topDown
        var id: Int { rawValue }
        var title: String { ["Daylight", "Lamplight", "Top Down"][rawValue] }
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private(set) var preset: Preset = .daylight
    private(set) var transparent = false
    private var sizeFactor: CGFloat = 1
    private(set) var currentArt: CGImage

    // Shared procedural textures (built once).
    private static let deskWood = Tex.wood(base: (0.50, 0.24, 0.11), seed: 11)
    private static let walnut = Tex.wood(size: 1024, base: (0.27, 0.15, 0.08), seed: 5)
    private static let oak = Tex.wood(size: 1024, base: (0.62, 0.42, 0.22), seed: 21)
    private static let grooves = Tex.grooveNormal()
    private static let recordSurface = Tex.recordSurface()
    private static let sheen = Tex.recordSheen()
    private static let envMap = Tex.environment()
    private static let gobo = Tex.blindsGobo()
    private static let ribs = Tex.ribNormal()
    private static let paintingImage = Tex.painting()
    private static let blob = Tex.shadowBlob()

    // Nodes we animate.
    private let room = SCNNode()
    private let wallGroup = SCNNode()
    private let lamp = SCNNode()
    private let turntable = SCNNode()
    private let spin = SCNNode()
    private let arm = SCNNode()
    private let sleeveHolder = SCNNode()
    private let sleeveTilt = SCNNode()
    private var sleeveBox = SCNNode()
    private let stand = SCNNode()
    private let stackNode = SCNNode()
    private let blobs = SCNNode()
    private let sun = SCNNode()
    private let lampOmni = SCNNode()
    private let lampSpot = SCNNode()
    private let frameGlow = SCNNode()
    private var labelMaterial = SCNMaterial()
    private var ledMaterial = SCNMaterial()
    private var shadeMaterial = SCNMaterial()
    private var bulbMaterial = SCNMaterial()
    private var sheenMaterial = SCNMaterial()

    private struct StackItem { let node: SCNNode; let dx: CGFloat; let dz: CGFloat; let yaw: CGFloat }
    private var stack: [StackItem] = []
    private var stackCounter: UInt64 = 0
    private let maxStack = 8
    private let sleeveSize: CGFloat = 3.15
    private let sleeveThickness: CGFloat = 0.05

    // Spin state.
    private var playing = false
    private var velocity: Double = 0
    private var lastTime: TimeInterval?
    private let fullSpeed = 2 * Double.pi * (100.0 / 3.0) / 60

    private let armRest: CGFloat = 0
    private let armPlay: CGFloat = -0.52

    init(art: CGImage? = nil) {
        currentArt = art ?? Tex.placeholderCover(seed: 0)
        scene.background.contents = NSColor.black
        scene.lightingEnvironment.contents = Self.envMap
        buildRoom()
        buildTurntable()
        buildSleeve()
        buildLamp()
        buildLights()
        buildCamera()
        scene.rootNode.addChildNode(stackNode)
