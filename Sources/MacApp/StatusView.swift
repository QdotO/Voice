import AppKit
import Foundation
import SwiftUI
import WhisperShared

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var state: DictationState {
        didSet {
            guard oldValue != state else { return }
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [.announcement: state.presentation.statusItemAccessibilityDescription]
            )
        }
    }
    @Published var lastText: String
    @Published var level: Float
    @Published var useCustomWaveColor: Bool
    @Published var waveColorHex: String

    init(
        state: DictationState = .loading,
        lastText: String = "",
        level: Float = 0,
        useCustomWaveColor: Bool = false,
        waveColorHex: String = ""
    ) {
        self.state = state
        self.lastText = lastText
        self.level = level
        self.useCustomWaveColor = useCustomWaveColor
        self.waveColorHex = waveColorHex
    }
}

/// Minimal floating status indicator
struct StatusView: View {
    @ObservedObject var viewModel: StatusViewModel
    let onAbort: (() -> Void)?
    let onRecovery: ((DictationRecoveryAction) -> Void)?

    init(
        viewModel: StatusViewModel,
        onAbort: (() -> Void)?,
        onRecovery: ((DictationRecoveryAction) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onAbort = onAbort
        self.onRecovery = onRecovery
    }

    var body: some View {
        DynamicIslandView(
            state: viewModel.state,
            level: viewModel.level,
            lastText: viewModel.lastText,
            onAbort: onAbort,
            onRecovery: onRecovery,
            useCustomWaveColor: viewModel.useCustomWaveColor,
            waveColorHex: viewModel.waveColorHex
        )
    }
}

// MARK: - Dynamic Dynamic Island

private struct DynamicIslandView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: DictationState
    let level: Float
    let lastText: String
    let onAbort: (() -> Void)?
    let onRecovery: ((DictationRecoveryAction) -> Void)?
    let useCustomWaveColor: Bool
    let waveColorHex: String

    var body: some View {
        HStack(spacing: 0) {
            // Dynamic Content
            dynamicContent
                .transition(reduceMotion ? .identity : .opacity)
                .padding(.leading, 12)

            Spacer(minLength: 0)
        }
        .frame(width: CGFloat(FloatingStatusLayout.islandWidth), height: 70)
        .background(
            Capsule()
                .fill(DesignSystem.Surface.inset)
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
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: level)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Whisper status")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var dynamicContent: some View {
        if state.isRecording {
            IslandWaveformView(
                level: level,
                useCustomWaveColor: useCustomWaveColor,
                waveColorHex: waveColorHex,
                reduceMotion: reduceMotion
            )
                .frame(width: 120, height: 48)
                .padding(.horizontal, 8)
        } else if case .processing = state {
            HStack(spacing: 8) {
                Text(state.presentation.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Text.primary)

                if let onAbort = onAbort {
                    Button(role: .cancel, action: onAbort) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.Text.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel transcription")
                    .accessibilityHint("Stops current transcription and returns to Ready")
                    .help("Cancel transcription")
                }
            }
            .padding(.horizontal, 8)
        } else if case .error = state {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.presentation.title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSystem.Text.primary)
                    if let detail = state.presentation.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(DesignSystem.Text.secondary)
                            .lineLimit(2)
                    }
                }

                if let action = state.presentation.recoveryAction, let onRecovery {
                    Button(recoveryLabel(for: action)) {
                        onRecovery(action)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(recoveryLabel(for: action))
                    .accessibilityHint(recoveryHint(for: action))
                    .help(recoveryHelp(for: action))
                }
            }
            .padding(.horizontal, 8)
        } else {
            HStack(spacing: 6) {
                Text(state.presentation.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Text.primary)

                if !lastText.isEmpty && state.isReady {
                    Text("•")
                        .foregroundStyle(DesignSystem.Text.tertiary)
                    Text(lastText)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(DesignSystem.Text.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func recoveryLabel(for action: DictationRecoveryAction) -> String {
        switch action {
        case .retry:
            return "Retry"
        case .openPermissions:
            return "Open Permissions"
        case .openSettings:
            return "Open Settings"
        }
    }

    private func recoveryHint(for action: DictationRecoveryAction) -> String {
        switch action {
        case .retry:
            return "Retries dictation"
        case .openPermissions:
            return "Opens System Settings so Whisper permissions can be enabled"
        case .openSettings:
            return "Opens Whisper settings"
        }
    }

    private func recoveryHelp(for action: DictationRecoveryAction) -> String {
        switch action {
        case .retry:
            return "Retry dictation"
        case .openPermissions:
            return "Open permissions"
        case .openSettings:
            return "Open Whisper settings"
        }
    }

    private var accessibilityValue: String {
        var values = [state.presentation.title]
        if let detail = state.presentation.detail, !detail.isEmpty {
            values.append(detail.replacingOccurrences(of: "\n", with: ". "))
        }
        if state.isReady && !lastText.isEmpty {
            values.append("Latest transcription: \(lastText)")
        }
        return values.joined(separator: ". ")
    }

    private var borderColors: [Color] {
        if state.isRecording || state == .processing {
            return state.isRecording
                ? [DesignSystem.States.active, DesignSystem.States.activeBright]
                : [DesignSystem.States.processing, DesignSystem.States.warning]
        } else if case .error = state {
            return [DesignSystem.States.danger, DesignSystem.States.warning]
        }
        return [DesignSystem.Stroke.strong, DesignSystem.Stroke.subtle]
    }
}

private struct IslandWaveformView: View {
    let level: Float
    let useCustomWaveColor: Bool
    let waveColorHex: String
    let reduceMotion: Bool

    @ViewBuilder
    var body: some View {
        if reduceMotion {
            waveform(tick: 0)
        } else {
            TimelineView(.animation) { context in
                let rawTick = Int(context.date.timeIntervalSinceReferenceDate * 12)
                // Noise gate so room hiss does not look like speech activity.
                let gatedLevel = max(0, min(1, (level - 0.12) / 0.88))
                // Keep near-silence mostly static instead of constantly flickering.
                let tick = gatedLevel < 0.02 ? 0 : rawTick
                waveform(tick: tick)
            }
        }
    }

    private func waveform(tick: Int) -> some View {
        let gatedLevel = max(0, min(1, (level - 0.12) / 0.88))
        return Text(ASCIIWavefield.make(level: gatedLevel, tick: tick))
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundStyle(
                LinearGradient(
                    colors: waveColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipped()
    }

    private var waveColors: [Color] {
        let selection = FloatingWaveColorResolver.resolve(
            useCustomColor: useCustomWaveColor,
            hex: waveColorHex
        )
        return [Color(statusHex: selection.primaryHex), Color(statusHex: selection.secondaryHex)]
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
        presentation.title
    }

    var presentationState: DictationPresentationState {
        switch self {
        case .loading:
            return .preparingModel
        case .ready:
            return .ready
        case .recording:
            return .listening
        case .processing:
            return .transcribing
        case let .error(detail):
            return .failure(
                kind: DictationStatePresentation.classifyFailure(detail),
                detail: detail
            )
        }
    }

    var presentation: DictationStatePresentation {
        DictationStatePresentation(state: presentationState)
    }

    var color: Color {
        switch self {
        case .loading: return DesignSystem.States.processing
        case .ready: return DesignSystem.States.success
        case .recording: return DesignSystem.States.active
        case .processing: return DesignSystem.States.processing
        case .error: return DesignSystem.States.danger
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

private extension Color {
    init(statusHex hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        let number = UInt32(value, radix: 16) ?? 0xFF6A32
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
