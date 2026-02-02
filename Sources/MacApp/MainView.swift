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

    @AppStorage("showStatusIndicator") private var showStatusIndicator = true
    @AppStorage("recordingMode") private var recordingMode = "hold"
    @AppStorage("autoStopEnabled") private var autoStopEnabled = true
    @AppStorage("autoStopSilenceSeconds") private var autoStopSilenceSeconds = 1.5
    @AppStorage("useCopilotAnalysis") private var useCopilotAnalysis = false
    @AppStorage("copilotBridgeURL") private var copilotBridgeURL = "http://127.0.0.1:32190/analyze"

    @State private var recentDictations: [DictationHistoryEntry] = []
    @State private var analysis = ThemesAnalysis.placeholder
    @State private var isAnalyzing = false
    @State private var lastAnalysisDate: Date?
    @State private var bridgeStatus: BridgeStatus = .unknown
    @State private var bridgeError: String?
    @State private var bridgeModel: String?
    @State private var isCheckingBridge = false

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
                    statsTile
                    themesTile
                    vocabularyTile
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            refreshHistory()
            refreshAnalysis()
            checkBridgeHealth()
        }
        .onChange(of: useCopilotAnalysis) { _ in
            checkBridgeHealth()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: DictationHistory.didChangeNotification)
        ) { _ in
            refreshHistory()
            refreshAnalysisDebounced()
        }
        .onReceive(NotificationCenter.default.publisher(for: VoiceMemoStore.didChangeNotification))
        { _ in
            refreshAnalysisDebounced()
        }
        .onReceive(bridgeTimer) { _ in
            checkBridgeHealth()
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
                Text("Bento dashboard for dictation and memos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                bridgeBadge

                Button("Reconnect") {
                    checkBridgeHealth()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCheckingBridge)

                Button("Settings") { openSettings() }
                    .buttonStyle(.bordered)
                Button("Voice Memos") { openVoiceMemos() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var bridgeBadge: some View {
        let status = bridgeStatus
        return HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
        .help(bridgeError ?? status.helpText)
    }

    private var dictationTile: some View {
        BentoTile(title: "Quick Dictation", subtitle: statusViewModel.state.label) {
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
        BentoTile(title: "Quick Voice Memo", subtitle: voiceMemoSubtitle) {
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

                    Text(formatDuration(voiceMemoManager.currentDuration))
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
        BentoTile(title: "Recent Dictations", subtitle: "Last 5") {
            VStack(alignment: .leading, spacing: 10) {
                if recentDictations.isEmpty {
                    Text("No dictations yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentDictations.prefix(5)) { entry in
                        HStack {
                            Text(entry.text.prefix(42))
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(timeString(entry.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Open History") {
                    openHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var statsTile: some View {
        let weekly = weeklyStats
        return BentoTile(title: "Weekly Stats", subtitle: "Last 7 days") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StatChip(label: "Dictations", value: "\(weekly.count)")
                    StatChip(label: "Minutes", value: String(format: "%.1f", weekly.minutes))
                }
                Text("Based on dictation history only.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var themesTile: some View {
        BentoTile(title: "Themes", subtitle: analysis.source) {
            VStack(alignment: .leading, spacing: 10) {
                Text(analysis.title)
                    .font(.system(size: 13, weight: .semibold))

                ForEach(analysis.bullets.prefix(3), id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if analysis.source == "copilot-error" {
                    Text("Copilot auth error detected. Using fallback analysis.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                HStack {
                    Button(isAnalyzing ? "Analyzing..." : "Refresh") {
                        refreshAnalysis()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAnalyzing)

                    Spacer()

                    Button("AI Settings") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var vocabularyTile: some View {
        BentoTile(title: "Vocabulary", subtitle: "Custom terms") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Update domain terms and proper nouns.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Open Vocabulary") {
                    openVocabulary()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
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

    private func refreshAnalysis() {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        let dictationTexts = history.allEntries().map { $0.text }
        let memoTexts = voiceMemoManager.memos.compactMap { $0.transcript }
        let combined = dictationTexts + memoTexts

        Task {
            let result = await ThemesAnalyzer.analyze(
                texts: combined,
                useCopilot: useCopilotAnalysis,
                copilotEndpoint: copilotBridgeURL
            )
            await MainActor.run {
                analysis = result
                isAnalyzing = false
                lastAnalysisDate = Date()
            }
        }
    }

    private func refreshAnalysisDebounced() {
        let now = Date()
        if let last = lastAnalysisDate, now.timeIntervalSince(last) < 2 {
            return
        }
        refreshAnalysis()
    }

    private func checkBridgeHealth() {
        guard useCopilotAnalysis else {
            bridgeStatus = .disabled
            bridgeError = nil
            bridgeModel = nil
            return
        }

        guard
            let url = URL(
                string: copilotBridgeURL.replacingOccurrences(of: "/analyze", with: "/health"))
        else {
            bridgeStatus = .error
            bridgeError = "Invalid bridge URL"
            return
        }

        isCheckingBridge = true
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
                else {
                    throw URLError(.badServerResponse)
                }

                let decoded = try JSONDecoder().decode(BridgeHealthResponse.self, from: data)
                await MainActor.run {
                    bridgeStatus = decoded.authReady ? .ready : .error
                    bridgeError = decoded.lastError
                    bridgeModel = decoded.model
                    isCheckingBridge = false
                }
            } catch {
                await MainActor.run {
                    bridgeStatus = .error
                    bridgeError = error.localizedDescription
                    bridgeModel = nil
                    isCheckingBridge = false
                }
            }
        }
    }

    private var statusLabel: String {
        if let model = bridgeModel, !model.isEmpty {
            return "\(bridgeStatus.label) (\(model))"
        }
        return bridgeStatus.label
    }

    private var bridgeTimer: Timer.TimerPublisher {
        Timer.publish(every: 15, on: .main, in: .common)
    }

    private var weeklyStats: (count: Int, minutes: Double) {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let entries = history.allEntries().filter { $0.timestamp >= sevenDaysAgo }
        let minutes = entries.reduce(0.0) { $0 + ($1.durationSeconds / 60.0) }
        return (entries.count, minutes)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(10)
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
                Text(formatDuration(memo.durationSeconds))
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

    private func formatDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct CompactWaveform: View {
    let level: Float
    private let barCount = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let barWidth = max((width / CGFloat(barCount)) - 2, 2)
            let normalized = CGFloat(min(max(level, 0.02), 1))

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = CGFloat(index) / CGFloat(barCount)
                    let mod = 0.35 + 0.65 * sin((phase * .pi * 2) + (normalized * 2))
                    let barHeight = max(4, height * normalized * mod)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0),
                                    Color(red: 0.3, green: 0.6, blue: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: barHeight)
                        .opacity(0.6 + (0.4 * normalized))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private enum BridgeStatus {
    case ready
    case error
    case disabled
    case unknown

    var label: String {
        switch self {
        case .ready: return "Copilot: Ready"
        case .error: return "Copilot: Error"
        case .disabled: return "Copilot: Off"
        case .unknown: return "Copilot: Unknown"
        }
    }

    var helpText: String {
        switch self {
        case .ready: return "Copilot bridge is reachable."
        case .error: return "Copilot bridge error."
        case .disabled: return "Copilot analysis is disabled."
        case .unknown: return "Bridge status not checked yet."
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .error: return .red
        case .disabled: return .gray
        case .unknown: return .orange
        }
    }
}

private struct BridgeHealthResponse: Codable {
    let ok: Bool
    let model: String?
    let lastError: String?
    let authReady: Bool
}
