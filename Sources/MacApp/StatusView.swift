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

    var body: some View {
        DynamicIslandView(
            state: viewModel.state,
            level: viewModel.level,
            lastText: viewModel.lastText,
            onAbort: onAbort
        )
    }
}

// MARK: - Dynamic Dynamic Island

private struct DynamicIslandView: View {
    let state: DictationState
    let level: Float
    let lastText: String
    let onAbort: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Dynamic Content
            dynamicContent
                .transition(.opacity.combined(with: .scale))
                .padding(.leading, 12)

            Spacer(minLength: 0)
        }
        .frame(height: 76)
        .frame(minWidth: state.isRecording ? 180 : 140, maxWidth: state.isRecording ? 180 : 320)
        .background(
            Capsule()
                .fill(Color.black)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: borderColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: state.isRecording ? 1.0 + CGFloat(level * 2.5) : 1.5
                )
                .opacity(state.isRecording ? 0.6 + Double(level * 0.4) : 0.3)
                .animation(.linear(duration: 0.1), value: level)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state)
    }

    @ViewBuilder
    private var dynamicContent: some View {
        if state.isRecording {
            IslandWaveformView(level: level)
                .frame(width: 120, height: 48)
                .padding(.horizontal, 8)
        } else if case .processing = state {
            HStack(spacing: 8) {
                Text("Processing...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)

                if let onAbort = onAbort {
                    Button(action: onAbort) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        } else {
            HStack(spacing: 6) {
                Text(state.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)

                if !lastText.isEmpty && state.isReady {
                    Text("•")
                        .foregroundColor(.gray)
                    Text(lastText)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var borderColors: [Color] {
        if state.isRecording || state == .processing {
            // Golden Hour Scheme: Orange -> Yellow
            return [
                Color(red: 1.0, green: 0.27, blue: 0.0), Color(red: 1.0, green: 0.84, blue: 0.0),
            ]
        } else if case .error = state {
            return [.red, .orange]
        }
        return [.white.opacity(0.15), .white.opacity(0.05)]
    }
}

private struct IslandWaveformView: View {
    let level: Float

    var body: some View {
        TimelineView(.animation) { context in
            let rawTick = Int(context.date.timeIntervalSinceReferenceDate * 12)
            // Noise gate so room hiss does not look like speech activity.
            let gatedLevel = max(0, min(1, (level - 0.12) / 0.88))
            // Keep near-silence mostly static instead of constantly flickering.
            let tick = gatedLevel < 0.02 ? 0 : rawTick

            Text(ASCIIWavefield.make(level: gatedLevel, tick: tick))
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.35, blue: 0.0),
                            Color(red: 1.0, green: 0.82, blue: 0.05),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipped()
        }
    }
}

private enum ASCIIWavefield {
    static func make(level: Float, tick: Int) -> String {
        let normalized = min(max(level, 0), 1)
        let cols = 23
        let rows = 3
        let charset: [Character] = [
            " ", ".", ":", "/", "\\", "+", "*", "#", "R", "W", "D", "L", "S",
        ]
        if normalized < 0.01 {
            let blank = String(repeating: " ", count: cols)
            return [blank, blank, blank].joined(separator: "\n")
        }

        let activeBias = 0.03 + (0.82 * Double(normalized))
        var rng = LCG(state: UInt64(max(tick, 1) * 113 + 19))
        var lines: [String] = []
        lines.reserveCapacity(rows)

        for row in 0..<rows {
            var line = ""
            line.reserveCapacity(cols)
            for col in 0..<cols {
                let center = abs(Double(col) - Double(cols - 1) / 2.0)
                let taper = 1.0 - (center / (Double(cols) / 2.0)) * 0.45
                let phase = sin((Double(col) * 0.55) + (Double(tick) * 0.42) + (Double(row) * 0.9))
                let wave = (phase * 0.5 + 0.5)
                let threshold = activeBias * taper * (0.6 + wave * 0.8)

                if rng.nextUnit() < threshold {
                    let floor = Int(Double(charset.count - 1) * max(0.06, Double(normalized)))
                    let idx = max(
                        1,
                        min(charset.count - 1, floor + rng.nextInt(max(1, charset.count - floor))))
                    line.append(charset[idx])
                } else {
                    line.append(" ")
                }
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}

private struct LCG {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }

    mutating func nextUnit() -> Double {
        Double(next() % 10_000) / 10_000.0
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
