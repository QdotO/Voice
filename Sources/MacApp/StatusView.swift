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

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 0) {
            // State Icon / Indicator
            ZStack {
                if state.isRecording {
                    // Recording Indicator
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .opacity(isAnimating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                        .onAppear { isAnimating = true }
                } else if case .processing = state {
                    // Processing Spinner
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                        .scaleEffect(0.8)
                } else {
                    // Ready/Idle State
                    Image(systemName: stateIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(stateColor)
                }
            }
            .frame(width: 24, height: 24)
            .padding(.leading, 12)

            // Dynamic Content
            dynamicContent
                .transition(.opacity.combined(with: .scale))

            Spacer(minLength: 0)
        }
        .frame(height: 44)
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
                .frame(width: 120, height: 24)
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

    private var stateIconName: String {
        switch state {
        case .loading: return "arrow.down.circle"
        case .ready: return "mic.fill"
        case .recording: return "waveform"
        case .processing: return "gear"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch state {
        case .loading: return .orange
        case .ready: return .white
        case .recording: return .red
        case .processing: return .blue
        case .error: return .red
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
            ChartDataWrapper(targetLevel: level, date: context.date)
        }
    }
}

private struct ChartDataWrapper: View {
    let targetLevel: Float
    let date: Date

    @State private var currentLevel: Float = 0.0
    private let barCount = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    count: barCount,
                    level: currentLevel,
                    date: date
                )
            }
        }
        .onChange(of: date) { oldDate, newDate in
            // Frame-by-frame smoothing
            // If target changes slowly (10Hz), this smoothes the 60Hz tween
            let diff = targetLevel - currentLevel
            // Adjust factor: 0.1 is smooth, 0.3 is snappy. 0.2 is good.
            currentLevel += diff * 0.2
        }
    }
}

private struct WaveformBar: View {
    let index: Int
    let count: Int
    let level: Float
    let date: Date

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.27, blue: 0.0),  // Burnt Orange
                        Color(red: 1.0, green: 0.84, blue: 0.0),  // Sunny Yellow
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4, height: height)
    }

    private var height: CGFloat {
        // Logarithmic-ish scaling for audio (makes quiet sounds visible, louds don't clip too hard)
        let rawLevel = CGFloat(min(max(level, 0.0), 1.0))
        // Power 0.8 boosts mids slightly
        let normalized = pow(rawLevel, 0.8)

        let center = CGFloat(count) / 2.0
        let dist = abs(CGFloat(index) - center)
        let maxDist = center

        let baseHeight: CGFloat = 5
        let variableHeight: CGFloat = 24 * normalized

        // Constant speed ripple to avoid phase jumps (Jitter Fix #1)
        // 8.0 rad/s is a steady energetic pulse
        let time = date.timeIntervalSinceReferenceDate
        let speed = 8.0

        // Add a secondary wave that moves faster but is quieter
        // This adds "shimmer" without breaking phase
        let wave1 = sin(time * speed + Double(index) * 0.6)
        let wave2 = sin(time * speed * 2.3 + Double(index) * 0.8) * 0.5

        // Combine waves
        let ripple = (wave1 + wave2) / 1.5 * 0.5 + 0.5

        // Shape factor (tapering to edges)
        let shapeFactor = 1.0 - (dist / maxDist) * 0.5

        // Breathing animation:
        // Idle: small amplitude (2.0)
        // Active: adds jitter/life but scales smoothly with level
        let breathing = CGFloat(ripple) * (2.0 + 8.0 * normalized)

        return baseHeight + (variableHeight * shapeFactor) + breathing
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
