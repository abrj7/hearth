import AppKit
import SceneKit

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Render one still of a preset. Used for the settings thumbnails and for `--snapshot`.
func renderStill(preset: TurntableScene.Preset, size: CGSize, art: CGImage?, stack: [CGImage], playing: Bool) -> NSImage {
    let s = TurntableScene(art: art)
    for a in stack { s.pushToStack(a, animated: false) }
    s.apply(preset: preset, animated: false)
    s.setPlaying(playing, animated: false)
    s.setPlatterAngle(0.6)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = s.scene
    renderer.pointOfView = s.cameraNode
    return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
}

let args = CommandLine.arguments

if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
    writePNG(Tex.appIcon(), to: args[i + 1])
    exit(0)
}

// Developer aid: `Vinyl --snapshot <dir> [--art cover.png]` writes one PNG per scene.
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    var art: CGImage?
    if let a = args.firstIndex(of: "--art"), a + 1 < args.count, let img = NSImage(contentsOfFile: args[a + 1]) {
        art = Tex.square(img)
    }
    let stack = (1...4).map { Tex.placeholderCover(seed: UInt64($0)) }
    for p in TurntableScene.Preset.allCases {
