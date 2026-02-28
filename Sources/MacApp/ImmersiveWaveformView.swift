import SwiftUI

/// A thin horizontal waveform bar (~18 px tall) that animates to voice level.
/// Designed for the top-right corner overlay in Immersive Mode.
struct ImmersiveWaveformView: View {
    @ObservedObject var viewModel: StatusViewModel

    private let barHeight: CGFloat = 18
    private let segmentCount: Int = 80

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let tick = context.date.timeIntervalSinceReferenceDate
            let gated = max(0, min(1, (viewModel.level - 0.08) / 0.92))

            Canvas { ctx, size in
                let segW = size.width / CGFloat(segmentCount)
                let midY = size.height / 2

                for i in 0..<segmentCount {
                    let x = CGFloat(i) * segW + segW / 2

                    // Sine wave driven by time + position + level
                    let phase1 = tick * 6.0 + Double(i) * 0.28
                    let phase2 = tick * 9.5 + Double(i) * 0.18
                    let wave = sin(phase1) * 0.6 + sin(phase2) * 0.4

                    // Height grows with amplitude; at zero level the line stays razor-thin
                    let maxAmp = size.height * 0.45
                    let amp = CGFloat(gated) * maxAmp * (0.4 + 0.6 * abs(CGFloat(wave)))

                    // Taper the edges
                    let edge = abs(CGFloat(i) - CGFloat(segmentCount) / 2) / (CGFloat(segmentCount) / 2)
                    let tapered = amp * (1.0 - edge * edge * 0.5)

                    let rect = CGRect(
                        x: x - segW * 0.35,
                        y: midY - tapered,
                        width: segW * 0.7,
                        height: max(1.5, tapered * 2)
                    )

                    // Orange → yellow gradient matching the existing Dynamic Island palette
                    let t = CGFloat(i) / CGFloat(segmentCount)
                    let r: CGFloat = 1.0
                    let g: CGFloat = 0.27 + t * 0.57    // 0.27 → 0.84
                    let b: CGFloat = 0.0
                    let alpha: CGFloat = 0.55 + CGFloat(gated) * 0.45

                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: segW * 0.3),
                        with: .color(Color(red: r, green: g, blue: b).opacity(alpha))
                    )
                }
            }
            .frame(height: barHeight)
        }
        .background(.clear)
    }
}
