import AppKit
import SceneKit

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Everything needed to render one still of the room.
struct StillOptions {
    var preset: DeskScene.Preset = .daylight
    var size = CGSize(width: 1512, height: 982)
    var art: CGImage?
    var stack: [CGImage] = []
    var playing = true
    var items: Set<DeskItem> = DeskItem.defaults
    var weather: Weather = .clear
    var sizeFactor: CGFloat = 1
    var title: String? = "Side One"
    var artist: String? = "Your music here"
}

/// Render one still. Used for the settings thumbnails and for `--snapshot`.
func renderStill(_ o: StillOptions) -> NSImage {
    let s = DeskScene(art: o.art)
    for a in o.stack { s.pushToStack(a, animated: false) }
    s.setItems(o.items, animated: false)
    s.setWeather(o.weather, animated: false)
    s.setSize(o.sizeFactor, animated: false)
    s.apply(preset: o.preset, animated: false)
    s.setTitle(o.title, artist: o.artist, animated: false)
    s.setPlaying(o.playing, animated: false)
    s.setPlatterAngle(0.6)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = s.scene
    renderer.pointOfView = s.cameraNode
    // A late timestamp so rain and snow are already falling in the still.
    return renderer.snapshot(atTime: 8, with: o.size, antialiasingMode: .multisampling4X)
}

let args = CommandLine.arguments
func argument(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if let path = argument("--icon") {
    writePNG(Tex.appIcon(), to: path)
    exit(0)
}

// Developer aid: `Hearth --snapshot <dir> [--art cover.png] [--items clock,candle] [--weather rain] [--size small]`
// writes one PNG per scene.
if let dir = argument("--snapshot") {
    var o = StillOptions()
    if let a = argument("--art"), let img = NSImage(contentsOfFile: a) { o.art = Tex.square(img) }
    if let list = argument("--items") { o.items = Set(list.split(separator: ",").compactMap { DeskItem(rawValue: String($0)) }) }
    if let w = argument("--weather"), let weather = Weather(rawValue: w) { o.weather = weather }
    if let s = argument("--size"), let i = AppState.sizeNames.firstIndex(where: { $0.lowercased() == s }) { o.sizeFactor = AppState.sizeFactors[i] }
    o.stack = (1...4).map { Tex.placeholderCover(seed: UInt64($0)) }
    for p in DeskScene.Preset.allCases {
        o.preset = p
        o.playing = p != .lamplight
        let img = renderStill(o)
        var rect = CGRect(origin: .zero, size: img.size)
        if let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            writePNG(cg, to: "\(dir)/\(p.title.replacingOccurrences(of: " ", with: "")).png")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
