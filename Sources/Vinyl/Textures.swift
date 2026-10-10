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
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

            // A shared flow field keeps neighbouring grain lines roughly parallel.
            let waves: [(CGFloat, CGFloat, CGFloat, CGFloat)] = (0..<5).map { _ in
                (r.f(3, 13) * k, CGFloat(Int(r.f(1, 3.99))), CGFloat(Int(r.f(0, 2.99))), r.f(0, 2 * .pi))
            }
            func warp(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                var v: CGFloat = 0
                for w in waves { v += w.0 * sin(2 * .pi * (w.1 * x / S + w.2 * y / S) + w.3) }
                return v
            }
            func stroke(_ y0: CGFloat, _ width: CGFloat, _ c: CGColor) {
                ctx.setStrokeColor(c)
                ctx.setLineWidth(width)
                for off in [-S, 0, S] {
                    ctx.beginPath()
                    var x: CGFloat = 0
                    ctx.move(to: CGPoint(x: 0, y: y0 + off + warp(0, y0)))
                    while x < S {
                        x += S / 64
                        ctx.addLine(to: CGPoint(x: x, y: y0 + off + warp(x, y0)))
                    }
                    ctx.strokePath()
                }
            }
            let dark: RGB = (base.0 * 0.3, base.1 * 0.26, base.2 * 0.22)
            let light: RGB = (min(1, base.0 * 1.55), min(1, base.1 * 1.6), min(1, base.2 * 1.7))

            // Broad tonal bands.
            for _ in 0..<110 {
                let isDark = r.f(0, 1) < 0.55
                stroke(r.f(0, S), r.f(30, 280) * k,
                       color(isDark ? dark : light, isDark ? r.f(0.03, 0.10) : r.f(0.02, 0.07)))
            }
            // Grain lines.
            for _ in 0..<3200 {
                let isDark = r.f(0, 1) < 0.7
                let w = (pow(r.f(0, 1), 3) * 7 + 0.8) * k
                stroke(r.f(0, S), w, color(isDark ? dark : light, isDark ? r.f(0.04, 0.24) : r.f(0.03, 0.12)))
            }
            // Short fibres.
            ctx.setLineWidth(max(1, k))
            for _ in 0..<45000 {
                let x = r.f(0, S), y = r.f(0, S), len = r.f(20, 150) * k
                ctx.setStrokeColor(color(dark, r.f(0.03, 0.10)))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y + warp(x, y)))
                ctx.addLine(to: CGPoint(x: x + len, y: y + warp(x + len, y)))
                ctx.strokePath()
            }
        }
    }

    // MARK: Vinyl record

    /// Tangent-space normal map of concentric grooves, with smooth gaps between "tracks".
    static func grooveNormal(size: Int = 2048) -> CGImage {
        var px = [UInt8](repeating: 255, count: size * size * 4)
        let c = Double(size) / 2
        var r = RNG(7)
        let rings = 4096
        let amp: [Double] = (0..<rings).map { _ in Double(r.f(0.45, 1)) }
        let gaps: [Double] = [0.455, 0.57, 0.69, 0.80, 0.895]
        px.withUnsafeMutableBufferPointer { buf in
            for y in 0..<size {
                for x in 0..<size {
                    let dx = (Double(x) + 0.5 - c) / c
                    let dy = (Double(y) + 0.5 - c) / c
                    let rad = max(1e-6, (dx * dx + dy * dy).squareRoot())
                    var slope = 0.0
                    if rad > 0.37 && rad < 0.972 {
                        var a = amp[Int(rad * Double(rings - 1))]
                        for g in gaps where abs(rad - g) < 0.005 { a = 0 }
                        slope = a * 0.85 * sin(rad * 2 * .pi * 150)
                    }
                    var nx = -slope * dx / rad, ny = -slope * dy / rad
                    let inv = 1 / (nx * nx + ny * ny + 1).squareRoot()
                    nx *= inv; ny *= inv
                    let i = (y * size + x) * 4
                    buf[i] = UInt8(max(0, min(255, (nx * 0.5 + 0.5) * 255)))
                    buf[i + 1] = UInt8(max(0, min(255, (ny * 0.5 + 0.5) * 255)))
                    buf[i + 2] = UInt8(max(0, min(255, (inv * 0.5 + 0.5) * 255)))
                }
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Record surface: near-black with faint concentric lines and paler track gaps.
    static func recordSurface() -> CGImage {
        draw(1024, 1024) { ctx in
            var r = RNG(3)
            ctx.setFillColor(color((0.022, 0.022, 0.026)))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            func ring(_ frac: CGFloat, _ width: CGFloat, _ alpha: CGFloat) {
                let rad = frac * 512
                ctx.setStrokeColor(color((1, 1, 1), alpha))
                ctx.setLineWidth(width)
                ctx.strokeEllipse(in: CGRect(x: 512 - rad, y: 512 - rad, width: rad * 2, height: rad * 2))
            }
            var f: CGFloat = 0.37
            while f < 0.97 { ring(f, 1, r.f(0.0, 0.035)); f += r.f(0.002, 0.006) }
            for g in [0.455, 0.57, 0.69, 0.80, 0.895] as [CGFloat] { ring(g, 4, 0.06) }
            ring(0.985, 6, 0.05)
        }
    }

    /// The two bright wedges light makes on a grooved record. Drawn on a disc that does not spin.
    static func recordSheen() -> CGImage {
        let size = 1024
        var px = [UInt8](repeating: 255, count: size * size * 4)
        var r = RNG(17)
        let noise: [Double] = (0..<512).map { _ in Double(r.f(0.6, 1)) }
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) + 0.5 - 512) / 512, dy = (Double(y) + 0.5 - 512) / 512
                let rad = (dx * dx + dy * dy).squareRoot()
                var v = 0.0
                if rad > 0.36 && rad < 0.975 {
                    let a = atan2(dy, dx)
                    v = pow(abs(cos(a - 0.6)), 46) * 0.62 + pow(abs(cos(a - 1.9)), 120) * 0.14
                    v *= noise[min(511, Int(rad * 511))]
                    v *= min(1, (rad - 0.36) / 0.04) * min(1, (0.975 - rad) / 0.02)
                }
                let i = (y * size + x) * 4
                let b = UInt8(max(0, min(255, v * 255)))
                px[i] = b; px[i + 1] = b; px[i + 2] = b
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Centre label for the record, cut from the album cover.
    static func label(from art: CGImage) -> CGImage {
        draw(512, 512) { ctx in
            let rect = CGRect(x: 0, y: 0, width: 512, height: 512)
            ctx.setFillColor(color((0.05, 0.05, 0.05)))
            ctx.fill(rect)
            ctx.addEllipse(in: rect)
            ctx.clip()
            ctx.draw(art, in: rect)
            ctx.setStrokeColor(color((0, 0, 0), 0.35))
            ctx.setLineWidth(6)
            ctx.strokeEllipse(in: rect.insetBy(dx: 3, dy: 3))
            ctx.setFillColor(color((0.08, 0.08, 0.08)))
            ctx.fillEllipse(in: CGRect(x: 256 - 22, y: 256 - 22, width: 44, height: 44))
        }
    }

    /// Aspect-fill an arbitrary image into a square.
    static func square(_ image: NSImage, size: Int = 1024) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return draw(size, size) { ctx in
            ctx.interpolationQuality = .high
            let w = CGFloat(cg.width), h = CGFloat(cg.height), S = CGFloat(size)
            let scale = S / min(w, h)
            ctx.draw(cg, in: CGRect(x: (S - w * scale) / 2, y: (S - h * scale) / 2, width: w * scale, height: h * scale))
        }
    }

    // MARK: Built-in artwork

    static let palettes: [(RGB, RGB, RGB)] = [
        ((0.86, 0.42, 0.20), (0.96, 0.87, 0.70), (0.13, 0.22, 0.30)),
        ((0.12, 0.30, 0.33), (0.93, 0.74, 0.42), (0.90, 0.88, 0.80)),
        ((0.90, 0.85, 0.74), (0.75, 0.25, 0.18), (0.16, 0.15, 0.14)),
        ((0.20, 0.22, 0.42), (0.95, 0.62, 0.50), (0.96, 0.92, 0.84)),
        ((0.55, 0.62, 0.45), (0.96, 0.90, 0.76), (0.25, 0.20, 0.15)),
        ((0.10, 0.10, 0.11), (0.85, 0.70, 0.35), (0.80, 0.78, 0.74)),
    ]

    /// A house-style sleeve used before any real album cover arrives (or when a cover can't be found).
    static func placeholderCover(seed: UInt64) -> CGImage {
        draw(1024, 1024) { ctx in
            var r = RNG(seed &+ 99)
            let p = palettes[Int(seed % UInt64(palettes.count))]
            let S: CGFloat = 1024
            ctx.setFillColor(color(p.0))
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
            switch seed % 3 {
            case 0: // rising sun with rings
                let cx = S * r.f(0.4, 0.6), cy = S * r.f(0.3, 0.45)
                for i in (0..<6).reversed() {
                    let rad = S * (0.14 + CGFloat(i) * 0.075)
                    ctx.setFillColor(color(i % 2 == 0 ? p.1 : p.0, i == 0 ? 1 : 0.9))
                    ctx.fillEllipse(in: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2))
                }
                ctx.setFillColor(color(p.2))
                ctx.fill(CGRect(x: 0, y: 0, width: S, height: cy - S * 0.08))
            case 1: // stacked arcs
                for i in 0..<7 {
                    let rad = S * (0.95 - CGFloat(i) * 0.12)
                    ctx.setFillColor(color(i % 2 == 0 ? p.1 : p.2, 1))
                    ctx.fillEllipse(in: CGRect(x: S * 0.5 - rad, y: -rad * 0.55, width: rad * 2, height: rad * 2))
                }
            default: // offset discs
                ctx.setFillColor(color(p.2))
                ctx.fillEllipse(in: CGRect(x: S * 0.14, y: S * 0.2, width: S * 0.6, height: S * 0.6))
