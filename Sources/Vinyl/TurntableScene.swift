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
        apply(preset: .daylight, animated: false)
    }

    // MARK: Materials

    private static func mat(_ contents: Any, rough: CGFloat, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = NSNumber(value: Double(rough))
        m.metalness.contents = NSNumber(value: Double(metal))
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        return m
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private func node(_ geometry: SCNGeometry, _ material: SCNMaterial, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geometry.materials = [material]
        let n = SCNNode(geometry: geometry)
        n.position = p
        return n
    }

    // MARK: Build

    private func buildRoom() {
        // Desk: deep enough that the top-down view never sees an edge.
        let deskMat = Self.mat(Self.deskWood, rough: 0.42)
        deskMat.diffuse.wrapS = .repeat
        deskMat.diffuse.wrapT = .repeat
        deskMat.diffuse.contentsTransform = SCNMatrix4MakeScale(2.4, 1.9, 1)
        let desk = node(SCNBox(width: 26, height: 0.6, length: 21, chamferRadius: 0), deskMat, at: SCNVector3(0, -0.3, -2.5))
        room.addChildNode(desk)

        let wallMat = Self.mat(Self.rgb(0.85, 0.81, 0.74), rough: 0.95)
        let wall = node(SCNPlane(width: 44, height: 26), wallMat, at: SCNVector3(0, 13, -3.2))
        wallGroup.addChildNode(wall)

        // Framed painting.
        let frame = SCNNode()
        frame.position = SCNVector3(1.3, 4.75, -3.2)
        let frameMat = Self.mat(Self.walnut, rough: 0.5)
        frame.addChildNode(node(SCNBox(width: 4.7, height: 3.5, length: 0.16, chamferRadius: 0.02), frameMat, at: SCNVector3(0, 0, 0.08)))
        frame.addChildNode(node(SCNPlane(width: 4.4, height: 3.2), Self.mat(Self.rgb(0.93, 0.91, 0.86), rough: 0.9), at: SCNVector3(0, 0, 0.165)))
        frame.addChildNode(node(SCNPlane(width: 3.5, height: 2.3), Self.mat(Self.paintingImage, rough: 0.7), at: SCNVector3(0, 0, 0.17)))
        wallGroup.addChildNode(frame)

        // Warm backlight behind the frame for the evening scene.
        let glow = SCNLight()
        glow.type = .omni
        glow.color = Self.rgb(1, 0.55, 0.25)
        glow.intensity = 0
        glow.attenuationStartDistance = 0
        glow.attenuationEndDistance = 5
        glow.attenuationFalloffExponent = 2
        frameGlow.light = glow
        frameGlow.position = SCNVector3(1.3, 4.75, -3.05)
        wallGroup.addChildNode(frameGlow)

        room.addChildNode(wallGroup)
        scene.rootNode.addChildNode(room)

        // Contact shadows for transparent mode.
        let blobMat = SCNMaterial()
        blobMat.lightingModel = .constant
        blobMat.diffuse.contents = Self.blob
        blobMat.writesToDepthBuffer = false
        for (x, z, w, d) in [(-0.2, 0.9, 6.6, 5.4), (-4.6, -0.1, 4.6, 2.2)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let b = node(SCNPlane(width: w, height: d), blobMat, at: SCNVector3(x, 0.005, z))
            b.eulerAngles.x = -.pi / 2
            blobs.addChildNode(b)
        }
        blobs.isHidden = true
        scene.rootNode.addChildNode(blobs)
    }

    private func buildTurntable() {
        turntable.name = "turntable"
        turntable.position = SCNVector3(-0.2, 0, 0.8)

        // Feet, walnut plinth, cream top plate.
        let rubber = Self.mat(Self.rgb(0.05, 0.05, 0.05), rough: 0.8)
        for (x, z) in [(-1.9, -1.45), (1.9, -1.45), (-1.9, 1.45), (1.9, 1.45)] as [(CGFloat, CGFloat)] {
            turntable.addChildNode(node(SCNCylinder(radius: 0.2, height: 0.08), rubber, at: SCNVector3(x, 0.04, z)))
        }
        let plinthMat = Self.mat(Self.walnut, rough: 0.45)
        turntable.addChildNode(node(SCNBox(width: 4.5, height: 0.4, length: 3.6, chamferRadius: 0.05), plinthMat, at: SCNVector3(0, 0.28, 0)))
        let cream = Self.mat(Self.rgb(0.87, 0.84, 0.77), rough: 0.55)
        turntable.addChildNode(node(SCNBox(width: 4.5, height: 0.1, length: 3.6, chamferRadius: 0.035), cream, at: SCNVector3(0, 0.53, 0)))
        let top: CGFloat = 0.58

