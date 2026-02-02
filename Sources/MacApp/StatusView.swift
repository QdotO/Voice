import AppKit
import Foundation
import SwiftUI

final class StatusViewModel: ObservableObject {
    @Published var state: DictationState
    @Published var lastText: String
    @Published var level: Float

    init(state: DictationState = .loading, lastText: String = "", level: Float = 0) {
        self.state = state
        self.lastText = lastText
        self.level = level
    }
}

/// Minimal floating status indicator
struct StatusView: View {
    @ObservedObject var viewModel: StatusViewModel
    let onAbort: (() -> Void)?
    @AppStorage("useCustomWaveColor") private var useCustomWaveColor = false
    @AppStorage("waveColorHex") private var waveColorHex = "#8B5CF6"

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(viewModel.state.color)
                    .frame(width: 10, height: 10)

                if viewModel.state.isRecording {
                    Circle()
                        .stroke(viewModel.state.color.opacity(0.5), lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .opacity(0.8)
                }
            }
            .shadow(color: viewModel.state.color.opacity(0.5), radius: 5, x: 0, y: 0)

            if viewModel.state.isRecording {
                EqualizerView(
                    level: viewModel.level,
                    useCustomColor: useCustomWaveColor,
                    colorHex: waveColorHex
                )
            }

            // Status text
            if !viewModel.state.isRecording {
                Text(viewModel.state.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)  // Always white on dark material
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            }

            if case .processing = viewModel.state {
                Button(action: { onAbort?() }) {
                    Text("Abort")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Cancel this transcription")
            }

            // Show last transcription if available
            if !viewModel.lastText.isEmpty && viewModel.state.isReady {
                Text(
                    "• \(viewModel.lastText.prefix(30))\(viewModel.lastText.count > 30 ? "..." : "")"
                )
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
    }
}

private struct EqualizerView: View {
    let level: Float
    let useCustomColor: Bool
    let colorHex: String

    private struct BarConfig {
        let phase: Double
        let speed: Double
        let scale: CGFloat
    }

    private let bars: [BarConfig] = [
        BarConfig(phase: 0.0, speed: 3.2, scale: 0.7),
        BarConfig(phase: 1.3, speed: 3.8, scale: 0.9),
        BarConfig(phase: 2.1, speed: 4.1, scale: 1.2),
        BarConfig(phase: 3.4, speed: 3.5, scale: 1.0),
        BarConfig(phase: 4.2, speed: 3.9, scale: 0.85),
        BarConfig(phase: 5.1, speed: 4.4, scale: 1.1),
        BarConfig(phase: 6.0, speed: 3.6, scale: 0.8),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<bars.count, id: \.self) { index in
                    bar(config: bars[index], time: time, index: index)
                }
            }
        }
    }

    private func bar(config: BarConfig, time: TimeInterval, index: Int) -> some View {
        let normalized = Double(min(max(level, 0.02), 1.0))
        let wave = 0.35 + 0.65 * (sin(time * config.speed + config.phase) * 0.5 + 0.5)
        let amplitude = (20 * wave + 10) * normalized
        let height = CGFloat(6 + amplitude * Double(config.scale))
        let opacity = 0.6 + 0.4 * wave
        let tintShift = Double(index) / Double(max(bars.count - 1, 1))

        // If not custom, use our "Nebula" gradient logic by default
        let baseColor = Color(hex: colorHex) ?? Color.purple
        let topColor =
            useCustomColor
            ? baseColor.lighter(by: 0.18 + tintShift * 0.12)
            : Color(hue: 0.7 - (tintShift * 0.1), saturation: 0.8, brightness: 1.0)  // Violet -> Blue

        let bottomColor =
            useCustomColor
            ? baseColor.darker(by: 0.12 + tintShift * 0.08)
            : Color(hue: 0.8 - (tintShift * 0.15), saturation: 1.0, brightness: 0.8)  // Purple -> Dark Blue

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [topColor.opacity(opacity), bottomColor.opacity(opacity)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 4, height: height)
            .shadow(color: bottomColor.opacity(0.4), radius: 4, y: 1)
    }
}

extension Color {
    fileprivate func lighter(by amount: Double) -> Color {
        adjustBrightness(by: abs(amount))
    }

    fileprivate func darker(by amount: Double) -> Color {
        adjustBrightness(by: -abs(amount))
    }

    fileprivate func adjustBrightness(by amount: Double) -> Color {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else { return self }
        let r = min(max(rgb.redComponent + CGFloat(amount), 0), 1)
        let g = min(max(rgb.greenComponent + CGFloat(amount), 0), 1)
        let b = min(max(rgb.blueComponent + CGFloat(amount), 0), 1)
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }

    fileprivate init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6 else { return nil }

        var int: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&int) else { return nil }

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

enum DictationState: Equatable {
    case loading
    case ready
    case recording
    case processing
    case error(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .loading: return "Loading model..."
        case .ready: return "Ready"
        case .recording: return "Listening..."
        case .processing: return "Processing..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .loading: return .orange
        case .ready: return .green
        case .recording: return .red
        case .processing: return .blue
        case .error: return .red
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusView(viewModel: StatusViewModel(state: .loading, lastText: ""), onAbort: nil)
        StatusView(viewModel: StatusViewModel(state: .ready, lastText: ""), onAbort: nil)
        StatusView(
            viewModel: StatusViewModel(state: .recording, lastText: "", level: 0.6), onAbort: nil)
        StatusView(viewModel: StatusViewModel(state: .processing, lastText: ""), onAbort: nil)
        StatusView(
            viewModel: StatusViewModel(
                state: .ready, lastText: "This is some transcribed text that was typed"),
            onAbort: nil
        )
    }
    .padding()
}
