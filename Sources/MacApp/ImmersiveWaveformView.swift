import SwiftUI
import WhisperShared

/// Full-screen, click-through recording treatment for Immersive Mode.
/// AppKit owns only the transparent window; SwiftUI owns state and animation.
struct ImmersiveWaveformView: View {
    @ObservedObject var viewModel: StatusViewModel
    let bottomInset: CGFloat
    let stopInstruction: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { viewModel.state.isRecording }

    var body: some View {
        ZStack(alignment: .bottom) {
            ambientGlow

            ImmersiveCapsule(viewModel: viewModel, stopInstruction: stopInstruction)
                .frame(maxWidth: 680)
                .padding(.horizontal, 36)
                .padding(.bottom, max(22, bottomInset + 18))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isRecording)
        // Decorative surface stays hidden; StatusViewModel posts one equivalent
        // announcement for each meaningful state transition.
        .accessibilityHidden(true)
    }

    private var ambientGlow: some View {
        ZStack {
            // Low-cost full-screen wash: keeps desktop visible while moving the
            // palette away from a muddy lower-third dimmer.
            LinearGradient(
                colors: [
                    .clear,
                    Color(red: 1.0, green: 0.42, blue: 0.30).opacity(isRecording ? 0.07 : 0.04),
                    Color(red: 1.0, green: 0.47, blue: 0.32).opacity(isRecording ? 0.24 : 0.14),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // One wide, bright bloom supplies the Claude-like lift behind the
            // capsule without a per-frame canvas or expensive blur pass.
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.70, blue: 0.54).opacity(isRecording ? 0.62 : 0.38),
                    Color(red: 1.0, green: 0.43, blue: 0.29).opacity(isRecording ? 0.36 : 0.20),
                    Color(red: 0.98, green: 0.28, blue: 0.24).opacity(isRecording ? 0.16 : 0.09),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 1.12),
                startRadius: 30,
                endRadius: 980
            )

            // Wide off-screen sources create soft coral spill at both edges.
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.38, blue: 0.34).opacity(isRecording ? 0.20 : 0.11),
                    .clear,
                ],
                center: UnitPoint(x: -0.08, y: 1.02),
                startRadius: 40,
                endRadius: 760
            )

            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.38, blue: 0.34).opacity(isRecording ? 0.20 : 0.11),
                    .clear,
                ],
                center: UnitPoint(x: 1.08, y: 1.02),
                startRadius: 40,
                endRadius: 760
            )
        }
        .ignoresSafeArea()
    }
}

private struct ImmersiveCapsule: View {
    @ObservedObject var viewModel: StatusViewModel
    let stopInstruction: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if viewModel.state.isRecording {
                    ClaudeStyleWaveform(level: viewModel.level)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ProcessingPulse()
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(maxWidth: .infinity)

            Text(viewModel.state.isRecording ? stopInstruction : viewModel.state.presentation.title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.82)
            .foregroundStyle(.white)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(capsuleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.75)
        )
        .shadow(color: Color(red: 1.0, green: 0.22, blue: 0.05).opacity(0.30), radius: 30, y: 12)
        .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: viewModel.state)
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.20, blue: 0.08).opacity(0.90),
                        Color(red: 0.98, green: 0.37, blue: 0.13).opacity(0.82),
                        Color(red: 0.70, green: 0.15, blue: 0.06).opacity(0.90),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

private struct ClaudeStyleWaveform: View {
    let level: Float
    private let count = 57

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        Group {
            if reduceMotion {
                staticWaveform
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let gated = CGFloat(max(0, min(1, (level - 0.07) / 0.93)))

                    Canvas { context, size in
                        let spacing = size.width / CGFloat(count)
                        let centerY = size.height / 2

                        for index in 0..<count {
                            let normalized = CGFloat(index) / CGFloat(count - 1)
                            let distance = abs(normalized - 0.5) * 2
                            let taper = pow(max(0, 1 - distance), 0.42)
                            let fastVoice = abs(sin(time * 7.2 + Double(index) * 0.53))
                            let slowVoice = abs(sin(time * 3.9 + Double(index) * 0.19))
                            let voice = fastVoice * 0.62 + slowVoice * 0.38
                            let activity = 0.10 + gated * CGFloat(voice) * taper
                            let height = max(3, min(size.height * 0.82, 3 + activity * size.height * 0.68))
                            let width = max(2.2, spacing * 0.42)
                            let rect = CGRect(
                                x: CGFloat(index) * spacing + (spacing - width) / 2,
                                y: centerY - height / 2,
                                width: width,
                                height: height
                            )
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: width / 2),
                                with: .color(.white.opacity(0.46 + Double(gated) * 0.48))
                            )
                        }
                    }
                }
            }
        }
        .frame(height: 34)
    }

    private var staticWaveform: some View {
        let gated = CGFloat(max(0, min(1, (level - 0.07) / 0.93)))
        return Canvas { context, size in
            let spacing = size.width / CGFloat(count)
            let centerY = size.height / 2

            for index in 0..<count {
                let normalized = CGFloat(index) / CGFloat(count - 1)
                let distance = abs(normalized - 0.5) * 2
                let taper = pow(max(0, 1 - distance), 0.42)
                let activity = 0.10 + gated * taper
                let height = max(3, min(size.height * 0.82, 3 + activity * size.height * 0.68))
                let width = max(2.2, spacing * 0.42)
                let rect = CGRect(
                    x: CGFloat(index) * spacing + (spacing - width) / 2,
                    y: centerY - height / 2,
                    width: width,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(.white.opacity(0.46 + Double(gated) * 0.48))
                )
            }
        }
    }
}

private struct ProcessingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if reduceMotion {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.65))
                            .frame(width: 6, height: 6)
                    }
                }

                Text("Transcribing…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { index in
                            let pulse = (sin(time * 5.5 - Double(index) * 0.9) + 1) / 2
                            Circle()
                                .fill(.white.opacity(0.35 + pulse * 0.60))
                                .frame(width: 5 + pulse * 2, height: 5 + pulse * 2)
                        }
                    }

                    Text("Transcribing…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
    }
}
