import AppKit
import CoreImage

/// Small deterministic RNG so every procedural texture looks the same on each launch.
struct RNG: RandomNumberGenerator {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567 }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func f(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let u = CGFloat(next() >> 11) / CGFloat(1 << 53)
        return a + (b - a) * u
    }
}

typealias RGB = (CGFloat, CGFloat, CGFloat)

/// Everything in the scene is drawn in code: no bundled image assets.
enum Tex {
    static let ci = CIContext()
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func color(_ c: RGB, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: srgb, components: [c.0, c.1, c.2, a])!
    }

    static func draw(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(ctx)
        return ctx.makeImage()!
    }

    static func blur(_ img: CGImage, _ sigma: Double) -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        let out = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: rect)
        return ci.createCGImage(out, from: rect) ?? img
    }

    // MARK: Wood

    /// Tileable wood grain. Grain runs along the image's x axis.
    static func wood(size: Int = 4096, base: RGB, seed: UInt64) -> CGImage {
        draw(size, size) { ctx in
            var r = RNG(seed)
            let S = CGFloat(size)
            let k = S / 4096
            ctx.setFillColor(color(base))
