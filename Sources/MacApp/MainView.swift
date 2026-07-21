import SwiftUI
import WhisperShared

struct MainView: View {
    @ObservedObject var voiceMemoManager: VoiceMemoManager
    @ObservedObject var statusViewModel: StatusViewModel
    let startDictation: () -> Void
    let stopDictation: () -> Void
    let openSettings: () -> Void
    let openHistory: () -> Void
    let openVoiceMemos: () -> Void
    let openVocabulary: () -> Void

    @AppStorage("selectedModel") private var selectedModel = "base.en"
    @AppStorage("showStatusIndicator") private var showStatusIndicator = true
    @AppStorage("recordingMode") private var recordingMode = "hold"

    @State private var recentDictations: [DictationHistoryEntry] = []

    private let history = DictationHistory.shared

    var body: some View {
        ZStack {
            DesignSystem.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    dictationTile
                    voiceMemoTile
                    historyTile
                    accuracyTile
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            refreshHistory()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: DictationHistory.didChangeNotification)
        ) { _ in
            refreshHistory()
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ]
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Whisper")
                    .font(.system(size: 26, weight: .semibold))
                Text("Offline dictation and voice memos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Settings") { openSettings() }
                    .buttonStyle(.bordered)
                Button("History") { openHistory() }
                    .buttonStyle(.bordered)
                Button("Voice Memos") { openVoiceMemos() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var dictationTile: some View {
        BentoTile(title: "Dictation", subtitle: statusViewModel.state.label) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: toggleDictation) {
                        Text(statusViewModel.state.isRecording ? "Stop" : "Start")
                            .frame(minWidth: 90)
                    }
                    .buttonStyle(.borderedProminent)

                    Toggle("Overlay", isOn: $showStatusIndicator)
                        .toggleStyle(.switch)
                }

                Picker("Recording Mode", selection: $recordingMode) {
                    Text("Hold").tag("hold")
                    Text("Toggle").tag("toggle")
                }
                .pickerStyle(.segmented)

                if statusViewModel.state.isReady {
                    Text("Ready to insert at the cursor.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(statusViewModel.state.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .gridCellColumns(1)
    }

    private var voiceMemoTile: some View {
        BentoTile(title: "Voice Memos", subtitle: voiceMemoSubtitle) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CompactWaveform(level: voiceMemoManager.recordingLevel)
                        .frame(width: 140, height: 28)
                        .opacity(voiceMemoManager.isRecording ? 1 : 0.35)

                    Button(action: toggleMemoRecording) {
                        ZStack {
                            Circle()
                                .fill(
                                    voiceMemoManager.isRecording
                                        ? Color.red : Color.white.opacity(0.15)
                                )
                                .frame(width: 42, height: 42)
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                .frame(width: 50, height: 50)
                            if voiceMemoManager.isRecording {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Text(TimeFormatter.formatDuration(voiceMemoManager.currentDuration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if voiceMemoManager.memos.isEmpty {
                    Text("No memos yet. Tap record to start a long session.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(voiceMemoManager.memos.prefix(3)) { memo in
                            VoiceMemoMiniRow(
                                memo: memo,
                                isPlaying: voiceMemoManager.currentlyPlayingID == memo.id,
                                onPlay: { voiceMemoManager.togglePlayback(for: memo) }
                            )
                        }
                    }
                }
            }
        }
        .gridCellColumns(1)
    }

    private var historyTile: some View {
        BentoTile(title: "History", subtitle: "Recent transcriptions") {
            VStack(alignment: .leading, spacing: 10) {
                if recentDictations.isEmpty {
                    Text("No dictations yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentDictations.prefix(5)) { entry in
                        HStack {
                            Text(String(entry.text.prefix(42)))
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(timeString(entry.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text("Corrections are learned automatically from accepted edits and reused in future prompts.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button("Open History") {
                    openHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var accuracyTile: some View {
        BentoTile(title: "Accuracy", subtitle: currentModelSelection.profile.displayName) {
            VStack(alignment: .leading, spacing: 10) {
                Text(currentModelSelection.profile.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    AccuracyMetric(
                        label: "Model",
                        value: currentModelSelection.rawModelOverride
                            ?? currentModelSelection.profile.defaultModelName
                    )
                    AccuracyMetric(
                        label: "Terms",
                        value: "\(Vocabulary.shared.enabledTerms.count)"
                    )
                    AccuracyMetric(
                        label: "Corrections",
                        value: "\(CorrectionEngine.shared.learnedCorrectionTexts.count)"
                    )
                }

                Text(
                    "Vocabulary stays editable in v2. Use the profile picker for normal operation and raw overrides only for debug cases."
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                HStack {
                    Button("Model Settings") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Vocabulary") {
                        openVocabulary()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var currentModelSelection: (profile: ModelProfile, rawModelOverride: String?) {
        LegacyAppPreferencesSettingsStore.resolveLegacyModel(selectedModel)
    }

    private var voiceMemoSubtitle: String {
        voiceMemoManager.isRecording ? "Recording" : "Ready"
    }

    private func toggleDictation() {
        if statusViewModel.state.isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func toggleMemoRecording() {
        if voiceMemoManager.isRecording {
            voiceMemoManager.stopRecording()
        } else {
            voiceMemoManager.startRecording()
        }
    }

    private func refreshHistory() {
        recentDictations = history.allEntries()
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct BentoTile<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }
}

private struct AccuracyMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct VoiceMemoMiniRow: View {
    let memo: VoiceMemo
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(memo.title)
                    .font(.system(size: 12, weight: .medium))
                Text(TimeFormatter.formatDuration(memo.durationSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if memo.isTranscribing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CompactWaveform: View {
    let level: Float
    private let barCount = 14
    private let particlesPerBar = 14

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let normalized = CGFloat(min(max(level, 0.02), 1))
                let spacing: CGFloat = 2
                let barWidth = max((size.width / CGFloat(barCount)) - spacing, 2)
                let centerY = size.height / 2
                let burst = max(0, (normalized - 0.6) / 0.4)
                let time = timeline.date.timeIntervalSinceReferenceDate

                for index in 0..<barCount {
                    let phase = CGFloat(index) / CGFloat(barCount)
                    let mod = 0.35 + 0.65 * sin((phase * .pi * 2) + (normalized * 2))
                    let barHeight = max(4, size.height * normalized * mod)
                    let originX = CGFloat(index) * (barWidth + spacing) + (barWidth / 2)

                    for particle in 0..<particlesPerBar {
                        let seed = (index + 1) * 1000 + particle * 17
                        let randX = pseudoRandom(seed)
                        let randY = pseudoRandom(seed + 1)
                        let randSize = pseudoRandom(seed + 2)
                        let randPhase = pseudoRandom(seed + 3)

                        let drift = sin(time * (1.2 + Double(randPhase) * 1.5) + Double(seed))
                        let lift = cos(time * (1.4 + Double(randPhase)) + Double(seed))
                        let jitterX = CGFloat(drift) * (1.2 + 4 * burst)
                        let jitterY = CGFloat(lift) * (1.0 + 6 * burst)

                        let x = originX + (randX - 0.5) * barWidth + jitterX
                        let y = centerY + (randY - 0.5) * barHeight + jitterY

                        let radius = 1.0 + randSize * (1.4 + (1.6 * normalized))
                        let color = particleColor(t: randY)
                            .opacity(0.25 + (0.55 * normalized))

                        let rect = CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
    }

    private func particleColor(t: CGFloat) -> Color {
        let clamped = min(max(t, 0), 1)
        let start = (r: 0.62, g: 0.46, b: 1.0)
        let end = (r: 0.3, g: 0.6, b: 1.0)
        let r = start.r + (end.r - start.r) * clamped
        let g = start.g + (end.g - start.g) * clamped
        let b = start.b + (end.b - start.b) * clamped
        return Color(red: r, green: g, blue: b)
    }

    private func pseudoRandom(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
