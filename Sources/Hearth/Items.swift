import AppKit
import SceneKit

/// Things you can put in the room. Each one can be switched on or off independently.
enum DeskItem: String, CaseIterable, Identifiable {
    case turntable, stack, lamp, clock, candle, calendar, window
    var id: String { rawValue }
    var title: String {
        switch self {
        case .turntable: return "Record player"
        case .stack: return "Played records"
        case .lamp: return "Lamp"
        case .clock: return "Clock"
        case .candle: return "Candle"
        case .calendar: return "Calendar"
        case .window: return "Window"
        }
    }
    var symbol: String {
        switch self {
        case .turntable: return "opticaldisc"
        case .stack: return "square.stack"
        case .lamp: return "lamp.table"
        case .clock: return "clock"
        case .candle: return "flame"
        case .calendar: return "calendar"
        case .window: return "cloud.sun"
        }
    }
    static let defaults: Set<DeskItem> = [.turntable, .stack, .lamp, .window]
}

// MARK: Digital clock

/// A walnut block with a dark glass face and glowing amber digits.
final class ClockItem {
    let node = SCNNode()
    private let face: SCNMaterial
    private var shown = ""

    init(wood: SCNMaterial) {
        let body = SCNBox(width: 2.3, height: 1.0, length: 0.75, chamferRadius: 0.09)
        body.materials = [wood]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.5, 0)

        face = DeskScene.mat(NSColor.black, rough: 0.18)
        let glass = SCNPlane(width: 2.02, height: 0.72)
        glass.cornerRadius = 0.06
        glass.materials = [face]
        let faceNode = SCNNode(geometry: glass)
        faceNode.position = SCNVector3(0, 0.5, 0.378)

        let tilt = SCNNode()
        tilt.eulerAngles.x = -0.1
        tilt.addChildNode(bodyNode)
        tilt.addChildNode(faceNode)
        node.addChildNode(tilt)
        refresh()
    }

    /// Redraw the digits if the minute changed. Returns true when something changed.
    @discardableResult
    func refresh(_ date: Date = Date()) -> Bool {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        let full = f.string(from: date)
        guard full != shown else { return false }
        shown = full
        // Split "8:42 PM" into the digits and the am/pm marker (absent on 24-hour clocks).
        let digits = String(full.unicodeScalars.filter { CharacterSet(charactersIn: "0123456789:.").contains($0) })
        let suffix = full.uppercased().contains("PM") ? "PM" : (full.uppercased().contains("AM") ? "AM" : "")
        let image = Tex.clockFace(time: digits, suffix: suffix)
        face.diffuse.contents = image
        face.emission.contents = image
        return true
    }

    func setNight(_ night: Bool) { face.emission.intensity = night ? 1.5 : 1.0 }
}

// MARK: Candle

/// A pillar candle on a brass dish. The flame flickers and, at night, lights the desk.
final class CandleItem {
    let node = SCNNode()
    private let flame = SCNNode()
    private let glow = SCNNode()
    private let light = SCNLight()
    private let waxMaterial: SCNMaterial
    private var baseIntensity: CGFloat = 0

    init() {
        let brass = DeskScene.mat(NSColor(srgbRed: 0.72, green: 0.53, blue: 0.26, alpha: 1), rough: 0.32, metal: 1)
        let dish = SCNCylinder(radius: 0.55, height: 0.05)
        dish.materials = [brass]
        let dishNode = SCNNode(geometry: dish)
        dishNode.position = SCNVector3(0, 0.025, 0)
        node.addChildNode(dishNode)
        let rim = SCNTorus(ringRadius: 0.55, pipeRadius: 0.03)
        rim.materials = [brass]
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, 0.05, 0)
        node.addChildNode(rimNode)

        waxMaterial = DeskScene.mat(NSColor(srgbRed: 0.93, green: 0.88, blue: 0.78, alpha: 1), rough: 0.65)
        waxMaterial.emission.contents = NSColor(srgbRed: 1, green: 0.62, blue: 0.3, alpha: 1)
        let wax = SCNCylinder(radius: 0.34, height: 1.05)
        wax.radialSegmentCount = 64
        wax.materials = [waxMaterial]
        let waxNode = SCNNode(geometry: wax)
        waxNode.position = SCNVector3(0, 0.05 + 0.525, 0)
        node.addChildNode(waxNode)

        let wick = SCNCylinder(radius: 0.012, height: 0.1)
        wick.materials = [DeskScene.mat(NSColor(white: 0.05, alpha: 1), rough: 0.9)]
        let wickNode = SCNNode(geometry: wick)
        wickNode.position = SCNVector3(0, 1.15, 0)
        node.addChildNode(wickNode)

        // Flame: a bright core inside a softer halo, both unlit so they always read as light.
        func blob(_ radius: CGFloat, _ color: NSColor, _ strength: CGFloat) -> SCNNode {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.black
            m.emission.contents = color
            m.emission.intensity = strength
            m.blendMode = .add
            m.writesToDepthBuffer = false
            let s = SCNSphere(radius: radius)
            s.materials = [m]
            let n = SCNNode(geometry: s)
            n.castsShadow = false
            return n
        }
        let core = blob(0.055, NSColor(srgbRed: 1, green: 0.9, blue: 0.62, alpha: 1), 3)
        core.scale = SCNVector3(1, 2.3, 1)
        let halo = blob(0.1, NSColor(srgbRed: 1, green: 0.5, blue: 0.12, alpha: 1), 0.8)
        halo.scale = SCNVector3(1, 2.0, 1)
        flame.addChildNode(halo)
        flame.addChildNode(core)
        flame.position = SCNVector3(0, 1.3, 0)
        node.addChildNode(flame)

        light.type = .omni
        light.color = NSColor(srgbRed: 1, green: 0.58, blue: 0.24, alpha: 1)
        light.intensity = 0
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 16
        light.attenuationFalloffExponent = 2
        glow.light = light
        glow.position = SCNVector3(0, 1.45, 0)
        node.addChildNode(glow)
    }

    /// `strength` is how much the flame should light the room (0 in daylight).
    func setLight(_ strength: CGFloat) {
        baseIntensity = strength
        light.intensity = strength
        waxMaterial.emission.intensity = strength > 0 ? 0.12 : 0.03
    }

    func flicker(at t: TimeInterval) {
        let n = sin(t * 9.1) * 0.5 + sin(t * 14.7 + 1.3) * 0.3 + sin(t * 23.3 + 0.4) * 0.2
        flame.scale = SCNVector3(1 + CGFloat(n) * 0.05, 1 + CGFloat(n) * 0.12, 1)
        flame.position.x = CGFloat(sin(t * 5.3)) * 0.008
        light.intensity = baseIntensity * (0.9 + CGFloat(n) * 0.1)
    }
}

// MARK: Wall calendar

/// A tear-off page calendar hanging on the wall.
final class CalendarItem {
    let node = SCNNode()
    private let page: SCNMaterial
    private var shownDay = -1

    init() {
        let paper = DeskScene.mat(NSColor(srgbRed: 0.9, green: 0.88, blue: 0.83, alpha: 1), rough: 0.85)
        page = DeskScene.mat(NSColor.white, rough: 0.8)
        // A block of pages: the top sheet carries today's date.
        let block = SCNBox(width: 1.7, height: 2.3, length: 0.09, chamferRadius: 0)
        block.materials = [page, paper, paper, paper, paper, paper]
        let blockNode = SCNNode(geometry: block)
        blockNode.position = SCNVector3(0, 0, 0.045)
        node.addChildNode(blockNode)

        let nail = SCNCylinder(radius: 0.035, height: 0.12)
        nail.materials = [DeskScene.mat(NSColor(white: 0.25, alpha: 1), rough: 0.4, metal: 1)]
        let nailNode = SCNNode(geometry: nail)
        nailNode.eulerAngles.x = .pi / 2
        nailNode.position = SCNVector3(0, 1.02, 0.1)
        node.addChildNode(nailNode)
        refresh()
    }

    @discardableResult
    func refresh(_ date: Date = Date()) -> Bool {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        guard day != shownDay else { return false }
        shownDay = day
        page.diffuse.contents = Tex.calendarPage(date)
        return true
    }
}

// MARK: Window

/// A window let into the wall. Behind it sits a painted sky that follows the weather,
/// with rain or snow falling between the sky and the frame.
final class WindowItem {
    static let size = CGSize(width: 4.4, height: 3.3)
    let node = SCNNode()
    private let sky = SCNMaterial()
    private let precipitation = SCNNode()
    private let glow = SCNLight()
    private(set) var weather: Weather = .clear
    private(set) var night = false

    init(wallColor: NSColor) {
        let w = Self.size.width, h = Self.size.height
        let depth: CGFloat = 0.7

        sky.lightingModel = .constant
        sky.diffuse.contents = NSColor.black
        let skyPlane = SCNPlane(width: w + 2.4, height: h + 2.0)
        skyPlane.materials = [sky]
        let skyNode = SCNNode(geometry: skyPlane)
        skyNode.position = SCNVector3(0, 0.2, -depth - 0.9)
        skyNode.castsShadow = false
        node.addChildNode(skyNode)

        func box(_ bw: CGFloat, _ bh: CGFloat, _ bl: CGFloat, _ m: SCNMaterial, _ p: SCNVector3) {
            let g = SCNBox(width: bw, height: bh, length: bl, chamferRadius: 0.012)
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = p
            node.addChildNode(n)
        }
        // The reveal: the thickness of the wall around the opening.
        let reveal = DeskScene.mat(wallColor, rough: 0.95)
        box(0.3, h + 0.6, depth, reveal, SCNVector3(-w / 2 - 0.15, 0, -depth / 2))
        box(0.3, h + 0.6, depth, reveal, SCNVector3(w / 2 + 0.15, 0, -depth / 2))
        box(w, 0.3, depth, reveal, SCNVector3(0, h / 2 + 0.15, -depth / 2))
        box(w, 0.3, depth, reveal, SCNVector3(0, -h / 2 - 0.15, -depth / 2))

        // Painted casing on the wall, sash bars set back in the opening, and a sill.
        let paint = DeskScene.mat(NSColor(srgbRed: 0.93, green: 0.91, blue: 0.86, alpha: 1), rough: 0.5)
        let c: CGFloat = 0.24
        box(c, h + 2 * c, 0.1, paint, SCNVector3(-w / 2 - c / 2, 0, 0.05))
        box(c, h + 2 * c, 0.1, paint, SCNVector3(w / 2 + c / 2, 0, 0.05))
        box(w, c, 0.1, paint, SCNVector3(0, h / 2 + c / 2, 0.05))
        box(w + 2 * c + 0.3, 0.12, 0.5, paint, SCNVector3(0, -h / 2 - 0.06, 0.2))
        let sashZ = -depth + 0.12
        box(0.1, h, 0.1, paint, SCNVector3(0, 0, sashZ))
        box(w, 0.1, 0.1, paint, SCNVector3(0, 0.25, sashZ))
        for x in [-w / 2 + 0.06, w / 2 - 0.06] { box(0.12, h, 0.1, paint, SCNVector3(x, 0, sashZ)) }
        for y in [-h / 2 + 0.06, h / 2 - 0.06] { box(w, 0.12, 0.1, paint, SCNVector3(0, y, sashZ)) }

        precipitation.position = SCNVector3(0, h / 2 + 0.5, -depth - 0.35)
        node.addChildNode(precipitation)

        // Sky light spilling into the room.
        glow.type = .omni
        glow.intensity = 0
        glow.attenuationStartDistance = 0
        glow.attenuationEndDistance = 9
        glow.attenuationFalloffExponent = 2
        let glowNode = SCNNode()
        glowNode.light = glow
        glowNode.position = SCNVector3(0, 0.2, 1.8)
        node.addChildNode(glowNode)

        set(weather: .clear, night: false)
    }

    func set(weather w: Weather, night n: Bool) {
        weather = w
        night = n
        sky.diffuse.contents = Tex.sky(w, night: n)
        glow.color = n ? NSColor(srgbRed: 0.45, green: 0.55, blue: 0.9, alpha: 1) : NSColor(srgbRed: 0.8, green: 0.88, blue: 1, alpha: 1)
        glow.intensity = n ? 16 : 22 * (0.4 + 0.6 * w.sunFactor)

        precipitation.removeAllParticleSystems()
        guard w.isPrecipitating else { return }
        let p = SCNParticleSystem()
        let box = SCNBox(width: Self.size.width + 1.6, height: 0.1, length: 0.5, chamferRadius: 0)
        p.emitterShape = box
        p.birthLocation = .volume
        p.emittingDirection = SCNVector3(0, -1, 0)
        p.isLightingEnabled = false
        p.blendMode = .alpha
        p.isAffectedByGravity = false
        p.particleImage = Tex.dot
        // Everything falls straight down so nothing drifts through the wall into the room.
        p.spreadingAngle = 0
        if w == .snow {
            p.birthRate = 80
            p.particleLifeSpan = 5.2
            p.particleVelocity = 0.8
            p.particleVelocityVariation = 0.35
            p.particleSize = 0.045
            p.particleSizeVariation = 0.03
            p.particleColor = NSColor(white: 1, alpha: n ? 0.75 : 0.95)
            p.warmupDuration = 6
        } else {
            p.birthRate = w == .storm ? 520 : 300
            p.particleLifeSpan = 0.55
            p.particleVelocity = 9
            p.particleVelocityVariation = 2
            p.particleSize = 0.016
            p.stretchFactor = 0.05
            p.particleColor = NSColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: n ? 0.35 : 0.55)
            p.warmupDuration = 1
        }
        precipitation.addParticleSystem(p)
    }
}
