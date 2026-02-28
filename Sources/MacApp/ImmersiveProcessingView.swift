import SwiftUI

/// A scanline-style processing bar that sweeps across the bottom edge of the screen
/// while Whisper is transcribing. Monochrome: black background, white beam, ASCII trail.
struct ImmersiveProcessingView: View {
    // ASCII chars scattered in the beam's wake
    private let trailChars: [Character] = Array(".:;|/\\-=+*#")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            // Use a fixed-seed LCG per time bucket so trail chars are stable between frames
            let bucket = Int(t * 15)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                Canvas { ctx, size in
                    // ── Black fill ──────────────────────────────────────────────
                    ctx.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.black))

                    // ── Two beams sweeping in opposite directions ───────────────
                    let beam1Pos = (t * 0.52).truncatingRemainder(dividingBy: 1.0)
                    let beam2Pos = ((t * 0.52) + 0.5).truncatingRemainder(dividingBy: 1.0)

                    for (pos, _) in [(beam1Pos, 0), (beam2Pos, 1)] {
                        let cx = CGFloat(pos) * w
                        let bW = w * 0.14

                        ctx.fill(
                            Path(CGRect(x: cx - bW / 2, y: 0, width: bW, height: h)),
                            with: .linearGradient(
                                Gradient(stops: [
                                    .init(color: .clear, location: 0.00),
                                    .init(color: .white.opacity(0.15), location: 0.25),
                                    .init(color: .white.opacity(0.95), location: 0.50),
                                    .init(color: .white.opacity(0.15), location: 0.75),
                                    .init(color: .clear, location: 1.00),
                                ]),
                                startPoint: CGPoint(x: cx - bW / 2, y: 0),
                                endPoint: CGPoint(x: cx + bW / 2, y: 0)
                            )
                        )
                    }

                    // ── ASCII trail behind beam1 ────────────────────────────────
                    let font = CTFont("Menlo" as CFString, size: h * 0.72)
                    let trailLen = w * 0.18
                    let charW = h * 0.55
                    let numChars = max(1, Int(trailLen / charW))
                    let trailStart = CGFloat(beam1Pos) * w - trailLen

                    var lcg = FastLCG(seed: UInt64(bucket * 97 + 13))
                    for i in 0..<numChars {
                        let cx = trailStart + CGFloat(i) * charW
                        guard cx >= 0 && cx < w else { continue }
                        let fade = CGFloat(i) / CGFloat(numChars)  // 0=near beam, bright → 1=end, dim
                        let alpha = (1.0 - fade) * 0.55
                        let ch = trailChars[Int(lcg.next() % UInt64(trailChars.count))]
                        let attrStr = NSAttributedString(
                            string: String(ch),
                            attributes: [
                                .font: font,
                                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
                            ]
                        )
                        attrStr.draw(at: CGPoint(x: cx, y: (h - h * 0.72) / 2))
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .background(.black)
    }
}

// Minimal LCG for deterministic char selection
private struct FastLCG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
