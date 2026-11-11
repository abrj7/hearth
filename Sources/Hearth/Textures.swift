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
                ctx.setFillColor(color(p.1, 0.92))
                ctx.fillEllipse(in: CGRect(x: S * 0.32, y: S * 0.14, width: S * 0.6, height: S * 0.6))
            }
            // Paper grain.
            for _ in 0..<9000 {
                ctx.setFillColor(color((0, 0, 0), r.f(0.01, 0.05)))
                ctx.fill(CGRect(x: r.f(0, S), y: r.f(0, S), width: 2, height: 2))
            }
        }
    }

    /// Abstract landscape for the frame on the wall.
    static func painting() -> CGImage {
        let img = draw(1024, 680) { ctx in
            var r = RNG(42)
            let W: CGFloat = 1024, H: CGFloat = 680
            let grad = CGGradient(colorsSpace: srgb, colors: [
                color((0.93, 0.62, 0.36)), color((0.95, 0.80, 0.58)), color((0.62, 0.70, 0.72)),
            ] as CFArray, locations: [0, 0.45, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H * 0.25), end: CGPoint(x: 0, y: H), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.setFillColor(color((0.99, 0.93, 0.78)))
            ctx.fillEllipse(in: CGRect(x: W * 0.58, y: H * 0.42, width: 150, height: 150))
            let hills: [RGB] = [(0.47, 0.46, 0.50), (0.33, 0.36, 0.38), (0.21, 0.26, 0.25), (0.12, 0.15, 0.14)]
            for (i, c) in hills.enumerated() {
                let baseY = H * (0.46 - CGFloat(i) * 0.1)
                let a1 = r.f(20, 60), a2 = r.f(10, 30), p1 = r.f(0, 6), p2 = r.f(0, 6), f1 = r.f(0.004, 0.009), f2 = r.f(0.012, 0.02)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: 0))
                var x: CGFloat = 0
                while x <= W {
                    ctx.addLine(to: CGPoint(x: x, y: baseY + a1 * sin(x * f1 + p1) + a2 * sin(x * f2 + p2)))
                    x += 8
                }
                ctx.addLine(to: CGPoint(x: W, y: 0))
                ctx.closePath()
                ctx.setFillColor(color(c))
                ctx.fillPath()
            }
        }
        return blur(img, 1.2)
    }

    // MARK: Lighting helpers

    /// Equirectangular room: bright ceiling, warm walls, dark floor, one soft window.
    static func environment() -> CGImage {
        let img = draw(1024, 512) { ctx in
            let grad = CGGradient(colorsSpace: srgb, colors: [
                color((0.16, 0.10, 0.06)), color((0.48, 0.40, 0.33)), color((0.80, 0.75, 0.68)), color((0.93, 0.90, 0.85)),
            ] as CFArray, locations: [0, 0.42, 0.6, 1])!
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
            ctx.setFillColor(color((1, 1, 1)))
            ctx.fill(CGRect(x: 120, y: 270, width: 170, height: 150))
            ctx.fill(CGRect(x: 640, y: 300, width: 90, height: 110))
        }
        return blur(img, 14)
    }

    /// Light shape for the sun: slatted blinds, slightly soft.
    static func blindsGobo() -> CGImage {
        let img = draw(1024, 1024) { ctx in
            ctx.setFillColor(color((0, 0, 0)))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            ctx.translateBy(x: 512, y: 512)
            ctx.rotate(by: -0.42)
            ctx.setFillColor(color((1, 1, 1)))
            for pane in 0..<2 {
                let x0 = CGFloat(pane) * 400 - 390
                for i in 0..<10 {
                    ctx.fill(CGRect(x: x0, y: CGFloat(i) * 64 - 320, width: 370, height: 40))
                }
            }
        }
        return blur(img, 5)
    }

    /// Vertical ribs for the glass lamp shade.
    static func ribNormal() -> CGImage {
        draw(64, 4) { ctx in
            for x in 0..<64 {
                let s = sin(Double(x) / 64 * 2 * .pi)
                ctx.setFillColor(color((CGFloat(0.5 + 0.28 * s), 0.5, 0.95)))
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: 4))
            }
        }
    }

    /// Brass button cap with an engraved skip glyph (two triangles and a bar).
    static func buttonCap(forward: Bool) -> CGImage {
        draw(128, 128) { ctx in
            ctx.setFillColor(color((0.78, 0.60, 0.30)))
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            if !forward {
                ctx.translateBy(x: 128, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            ctx.setFillColor(color((0.16, 0.10, 0.04)))
            for x0 in [36, 60] as [CGFloat] {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x0, y: 44))
                ctx.addLine(to: CGPoint(x: x0 + 24, y: 64))
                ctx.addLine(to: CGPoint(x: x0, y: 84))
                ctx.closePath()
                ctx.fillPath()
            }
            ctx.fill(CGRect(x: 86, y: 44, width: 7, height: 40))
        }
    }

    /// Small printed card naming the song, like a label beside a record in a shop.
    static func titleCard(title: String, artist: String) -> CGImage {
        draw(1024, 400) { ctx in
            var r = RNG(8)
            ctx.setFillColor(color((0.93, 0.90, 0.83)))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 400))
            for _ in 0..<5000 {
                ctx.setFillColor(color((0.3, 0.2, 0.1), r.f(0.01, 0.05)))
                ctx.fill(CGRect(x: r.f(0, 1024), y: r.f(0, 400), width: 2, height: 2))
            }
            ctx.setStrokeColor(color((0.25, 0.18, 0.12), 0.55))
            ctx.setLineWidth(3)
            ctx.stroke(CGRect(x: 26, y: 26, width: 972, height: 348))

            let ink = NSColor(srgbRed: 0.15, green: 0.11, blue: 0.08, alpha: 1)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
                let base = NSFont.systemFont(ofSize: size, weight: weight)
                return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: "NOW PLAYING", attributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .kern: 9,
                .foregroundColor: NSColor(srgbRed: 0.62, green: 0.33, blue: 0.14, alpha: 1), .paragraphStyle: para,
            ]).draw(in: CGRect(x: 60, y: 290, width: 904, height: 44))
            // Shrink long titles a little before truncating them.
            let size: CGFloat = title.count > 26 ? 66 : 84
            NSAttributedString(string: title, attributes: [.font: serif(size, .semibold), .foregroundColor: ink, .paragraphStyle: para])
                .draw(in: CGRect(x: 60, y: 150, width: 904, height: size * 1.3))
            NSAttributedString(string: artist, attributes: [.font: serif(46, .regular), .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: para])
                .draw(in: CGRect(x: 60, y: 62, width: 904, height: 62))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Soft contact shadow used when the room is hidden.
    static func shadowBlob() -> CGImage {
        draw(256, 256) { ctx in
            let grad = CGGradient(colorsSpace: srgb, colors: [color((0, 0, 0), 0.55), color((0, 0, 0), 0.25), color((0, 0, 0), 0)] as CFArray, locations: [0, 0.6, 1])!
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }
    }

    // MARK: Desk items

    private static func drawText(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Glowing amber digits on dark glass.
    static func clockFace(time: String, suffix: String) -> CGImage {
        draw(1024, 368) { ctx in
            ctx.setFillColor(color((0.025, 0.022, 0.02)))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 368))
            let amber = NSColor(srgbRed: 1, green: 0.66, blue: 0.26, alpha: 1)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
                let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            }
            let shadow = NSShadow()
            shadow.shadowColor = amber.withAlphaComponent(0.7)
            shadow.shadowBlurRadius = 26
            drawText(ctx) {
                let shift: CGFloat = suffix.isEmpty ? 0 : -50
                NSAttributedString(string: time, attributes: [.font: rounded(250, .semibold), .foregroundColor: amber, .paragraphStyle: para, .shadow: shadow])
                    .draw(in: CGRect(x: shift, y: 26, width: 1024, height: 300))
                if !suffix.isEmpty {
                    NSAttributedString(string: suffix, attributes: [.font: rounded(64, .semibold), .foregroundColor: amber.withAlphaComponent(0.85), .shadow: shadow])
                        .draw(at: CGPoint(x: 868, y: 70))
                }
            }
        }
    }

    /// One page of a tear-off calendar.
    static func calendarPage(_ date: Date) -> CGImage {
        draw(680, 920) { ctx in
            var r = RNG(5)
            ctx.setFillColor(color((0.96, 0.94, 0.89)))
            ctx.fill(CGRect(x: 0, y: 0, width: 680, height: 920))
            for _ in 0..<5000 {
                ctx.setFillColor(color((0.3, 0.2, 0.1), r.f(0.01, 0.04)))
                ctx.fill(CGRect(x: r.f(0, 680), y: r.f(0, 920), width: 2, height: 2))
            }
            ctx.setFillColor(color((0.72, 0.23, 0.16)))
            ctx.fill(CGRect(x: 0, y: 700, width: 680, height: 220))
            ctx.setFillColor(color((0.2, 0.15, 0.12), 0.8))
            for x in [200, 480] as [CGFloat] { ctx.fillEllipse(in: CGRect(x: x - 14, y: 868, width: 28, height: 28)) }

            let f = DateFormatter()
            func text(_ format: String) -> String { f.dateFormat = format; return f.string(from: date) }
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let ink = NSColor(srgbRed: 0.14, green: 0.11, blue: 0.09, alpha: 1)
            func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
                let base = NSFont.systemFont(ofSize: size, weight: weight)
                return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            }
            drawText(ctx) {
                NSAttributedString(string: text("MMMM").uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 62, weight: .bold), .kern: 10, .foregroundColor: NSColor(white: 1, alpha: 0.95), .paragraphStyle: para])
                    .draw(in: CGRect(x: 0, y: 742, width: 680, height: 84))
                NSAttributedString(string: text("d"), attributes: [.font: serif(430, .bold), .foregroundColor: ink, .paragraphStyle: para])
                    .draw(in: CGRect(x: 0, y: 190, width: 680, height: 500))
                NSAttributedString(string: text("EEEE").uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 52, weight: .semibold), .kern: 8, .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: para])
                    .draw(in: CGRect(x: 0, y: 84, width: 680, height: 70))
            }
        }
    }

    /// The view out of the window for a given kind of weather, by day or by night.
    static func sky(_ w: Weather, night: Bool) -> CGImage {
        let W: CGFloat = 1024, H: CGFloat = 768
        var top: RGB, low: RGB, cloud: RGB
        var clouds: Int
        switch w {
        case .clear: top = (0.30, 0.56, 0.90); low = (0.80, 0.90, 0.98); cloud = (1, 1, 1); clouds = 2
        case .partly: top = (0.34, 0.58, 0.88); low = (0.82, 0.90, 0.97); cloud = (1, 1, 1); clouds = 8
        case .cloudy: top = (0.58, 0.62, 0.67); low = (0.80, 0.82, 0.84); cloud = (0.70, 0.72, 0.75); clouds = 18
        case .fog: top = (0.78, 0.79, 0.80); low = (0.86, 0.86, 0.85); cloud = (0.9, 0.9, 0.9); clouds = 4
        case .rain: top = (0.36, 0.40, 0.46); low = (0.60, 0.63, 0.66); cloud = (0.30, 0.33, 0.38); clouds = 20
        case .snow: top = (0.72, 0.75, 0.80); low = (0.90, 0.91, 0.93); cloud = (0.82, 0.84, 0.87); clouds = 14
        case .storm: top = (0.17, 0.19, 0.24); low = (0.40, 0.42, 0.46); cloud = (0.12, 0.13, 0.17); clouds = 22
        }
        let clearish = w == .clear || w == .partly
        if night {
            top = clearish ? (0.02, 0.035, 0.10) : (0.05, 0.055, 0.075)
            low = clearish ? (0.09, 0.13, 0.26) : (0.12, 0.13, 0.16)
            cloud = clearish ? (0.16, 0.19, 0.30) : (0.09, 0.10, 0.13)
        }
        var r = RNG(UInt64(w.hashValue & 0xFF) &+ 31)
        r = RNG(UInt64(Weather.allCases.firstIndex(of: w) ?? 0) &+ 31)

        let base = draw(Int(W), Int(H)) { ctx in
            let grad = CGGradient(colorsSpace: srgb, colors: [color(low), color(top)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H * 0.15), end: CGPoint(x: 0, y: H), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            if clearish && !night {
                let sun = CGGradient(colorsSpace: srgb, colors: [color((1, 0.98, 0.88), 0.95), color((1, 0.95, 0.8), 0)] as CFArray, locations: [0, 1])!
                ctx.drawRadialGradient(sun, startCenter: CGPoint(x: 790, y: 600), startRadius: 0, endCenter: CGPoint(x: 790, y: 600), endRadius: 260, options: [])
            }
            for _ in 0..<clouds {
                let cx = r.f(-60, W + 60), cy = r.f(H * 0.3, H * 0.98), scale = r.f(0.6, 1.5)
                for _ in 0..<7 {
                    let ew = r.f(90, 220) * scale, eh = ew * r.f(0.32, 0.5)
                    ctx.setFillColor(color(cloud, night ? 0.6 : r.f(0.55, 0.9)))
                    ctx.fillEllipse(in: CGRect(x: cx + r.f(-120, 120) * scale - ew / 2, y: cy + r.f(-30, 30) * scale - eh / 2, width: ew, height: eh))
                }
            }
        }
        let soft = blur(base, 11)

        return draw(Int(W), Int(H)) { ctx in
            ctx.draw(soft, in: CGRect(x: 0, y: 0, width: W, height: H))
            if night && clearish {
                for _ in 0..<170 {
                    let size = r.f(1.2, 3.4)
                    ctx.setFillColor(color((1, 1, 0.95), r.f(0.3, 0.95)))
                    ctx.fillEllipse(in: CGRect(x: r.f(0, W), y: r.f(H * 0.28, H), width: size, height: size))
                }
                let halo = CGGradient(colorsSpace: srgb, colors: [color((0.85, 0.9, 1), 0.35), color((0.85, 0.9, 1), 0)] as CFArray, locations: [0, 1])!
                ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 760, y: 590), startRadius: 0, endCenter: CGPoint(x: 760, y: 590), endRadius: 150, options: [])
                ctx.setFillColor(color((0.96, 0.96, 0.9)))
                ctx.fillEllipse(in: CGRect(x: 760 - 42, y: 590 - 42, width: 84, height: 84))
            }
            // Distant hills, then a nearer line of trees.
            let snowy = w == .snow
            var hills: [RGB] = snowy ? [(0.80, 0.83, 0.87), (0.66, 0.70, 0.75)] : [(0.42, 0.52, 0.50), (0.22, 0.32, 0.28)]
            if !clearish && !snowy { hills = [(0.40, 0.44, 0.46), (0.24, 0.28, 0.29)] }
            if night { hills = [(0.045, 0.06, 0.09), (0.02, 0.028, 0.045)] }
            for (i, c) in hills.enumerated() {
                let baseY = H * (0.30 - CGFloat(i) * 0.09)
                let a1 = r.f(18, 40), a2 = r.f(6, 16), p1 = r.f(0, 6), p2 = r.f(0, 6)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: 0))
                var x: CGFloat = 0
                while x <= W {
                    let bumps = i == 1 ? abs(sin(x * 0.09 + p2)) * 14 : 0
                    ctx.addLine(to: CGPoint(x: x, y: baseY + a1 * sin(x * 0.006 + p1) + a2 * sin(x * 0.02 + p2) + bumps))
                    x += 4
                }
                ctx.addLine(to: CGPoint(x: W, y: 0))
                ctx.closePath()
                ctx.setFillColor(color(c))
                ctx.fillPath()
            }
            if night {
                // A few lit windows far away.
                for _ in 0..<9 {
                    ctx.setFillColor(color((1, 0.78, 0.42), r.f(0.5, 0.95)))
                    ctx.fill(CGRect(x: r.f(40, W - 40), y: r.f(H * 0.06, H * 0.2), width: 5, height: 6))
                }
            }
            if w == .fog {
                ctx.setFillColor(color((0.86, 0.86, 0.85), night ? 0.25 : 0.6))
                ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            }
        }
    }

    /// Soft round dot used for snowflakes and raindrops.
    static let dot: CGImage = draw(32, 32) { ctx in
        let g = CGGradient(colorsSpace: srgb, colors: [color((1, 1, 1), 1), color((1, 1, 1), 0.8), color((1, 1, 1), 0)] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }

    /// App icon: a candle flame on a warm tile.
    static func appIcon() -> CGImage {
        draw(1024, 1024) { ctx in
            let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
            ctx.clip()
            let bg = CGGradient(colorsSpace: srgb, colors: [color((0.20, 0.10, 0.06)), color((0.42, 0.20, 0.10))] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
            let glow = CGGradient(colorsSpace: srgb, colors: [color((1, 0.62, 0.22), 0.55), color((1, 0.5, 0.15), 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540), endRadius: 400, options: [])
            func flame(_ scale: CGFloat, _ c: RGB) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 512, y: 300))
                p.addCurve(to: CGPoint(x: 512, y: 300 + 470 * scale), control1: CGPoint(x: 512 - 290 * scale, y: 300 + 60 * scale), control2: CGPoint(x: 512 - 60 * scale, y: 300 + 300 * scale))
                p.addCurve(to: CGPoint(x: 512, y: 300), control1: CGPoint(x: 512 + 60 * scale, y: 300 + 300 * scale), control2: CGPoint(x: 512 + 290 * scale, y: 300 + 60 * scale))
                ctx.addPath(p)
                ctx.setFillColor(color(c))
                ctx.fillPath()
            }
            flame(1, (0.98, 0.52, 0.16))
            flame(0.66, (1, 0.76, 0.32))
            flame(0.36, (1, 0.95, 0.75))
            ctx.setFillColor(color((0.93, 0.88, 0.78)))
            ctx.fill(CGRect(x: 512 - 120, y: 100, width: 240, height: 170))
            ctx.setFillColor(color((0.1, 0.07, 0.05)))
            ctx.fill(CGRect(x: 512 - 5, y: 262, width: 10, height: 46))
        }
    }
}
