import SwiftUI
import WhisperShared

struct VoiceMemosView: View {
    @ObservedObject var manager: VoiceMemoManager
    @State private var renameTarget: VoiceMemo?
    @State private var renameText = ""
    @State private var selectedMemoID: UUID?
    @State private var pendingDestructiveAction: VoiceMemoDestructiveAction?
    @FocusState private var focusedMemoID: UUID?

    var body: some View {
        ZStack {
            DesignSystem.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if manager.memos.isEmpty {
                    emptyState
                } else {
                    HSplitView {
                        memoList
                        memoDetail
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(
            minWidth: WhisperWindowLayout.voiceMemosMinimum.width,
            minHeight: WhisperWindowLayout.voiceMemosMinimum.height
        )
        .alert("Rename Memo", isPresented: renameBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Save") {
                if let memo = renameTarget {
                    manager.renameMemo(memo, title: renameText)
                }
                renameTarget = nil
            }
        }
        .alert(item: $pendingDestructiveAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.confirmButtonTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        }
        .onAppear {
            ensureSelection()
        }
        .onChange(of: manager.memos) {
            ensureSelection()
        }
    }

    private var memoList: some View {
        List(selection: $selectedMemoID) {
            ForEach(manager.memos) { memo in
                VoiceMemoRow(
                    memo: memo,
                    isPlaying: manager.currentlyPlayingID == memo.id,
                    isSelected: selectedMemoID == memo.id,
                    isFocused: focusedMemoID == memo.id,
                    onPlay: { manager.togglePlayback(for: memo) },
                    onRename: { openRename(memo) },
                    onShare: { manager.audioURL(for: memo) },
                    onExport: { manager.exportMemo(memo) },
                    onRetranscribe: { manager.retranscribe(memo) },
                    onToggleTranscribe: { manager.toggleAutoTranscribe(memo) },
                    onDelete: { pendingDestructiveAction = .delete(memo) }
                )
                .tag(memo.id)
                .focused($focusedMemoID, equals: memo.id)
                .focusable()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)
        .background(Color.black.opacity(0.15))
    }

    private var memoDetail: some View {
        Group {
            if let memo = selectedMemo {
                VoiceMemoDetailView(memo: memo, manager: manager)
            } else {
                memoDetailPlaceholder
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var memoDetailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Select a memo")
                .font(.headline)
            Text("Choose a recording to preview its transcript and waveform.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedMemo: VoiceMemo? {
        manager.memos.first { $0.id == selectedMemoID }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { newValue in
                if !newValue {
                    renameTarget = nil
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Memos")
                    .font(.system(size: 20, weight: .semibold))
                Text("Long-running sessions with playback and transcripts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                manager.retranscribeMissingTimings()
            } label: {
                Label("Re-transcribe Missing", systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .disabled(missingTimingsCount == 0)

            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    RecordingWaveform(level: manager.recordingLevel)
                        .frame(width: 120, height: 36)
                        .opacity(manager.isRecording ? 1 : 0.35)

                    Button(action: toggleRecording) {
                        Label(
                            manager.isRecording ? "Stop Recording" : "Record",
                            systemImage: manager.isRecording ? "stop.fill" : "record.circle"
                        )
                        .frame(minHeight: DesignSystem.ControlHeight.primary)
                    }
                    .buttonStyle(.whisperPrimary())
                    .accessibilityLabel(
                        manager.isRecording ? "Stop recording voice memo" : "Record voice memo"
                    )
                    .accessibilityValue(
                        VoiceMemoAccessibility.durationValue(manager.currentDuration)
                    )
                    .accessibilityHint(
                        manager.isRecording
                            ? "Stops and saves current voice memo"
                            : "Starts a new voice memo recording"
                    )
                    .help(manager.isRecording ? "Stop recording" : "Record voice memo")
                }

                Text(TimeFormatter.formatDuration(manager.currentDuration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(
                            colors: [.black, .clear], startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 20)
                    }
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No memos yet")
                .font(.headline)
            Text("Tap the record button to start a long session.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleRecording() {
        if manager.isRecording {
            manager.stopRecording()
        } else {
            manager.startRecording()
        }
    }

    private func openRename(_ memo: VoiceMemo) {
        renameTarget = memo
        renameText = memo.title
    }

    private func ensureSelection() {
        if selectedMemoID == nil || selectedMemo == nil {
            selectedMemoID = manager.memos.first?.id
        }
    }

    private func perform(_ action: VoiceMemoDestructiveAction) {
        switch action {
        case .delete(let memo):
            manager.deleteMemo(memo)
            ensureSelection()
        }
    }

    private var missingTimingsCount: Int {
        manager.memos.filter { ($0.transcriptWords?.isEmpty ?? true) && !$0.isTranscribing }.count
    }
}

private struct VoiceMemoRow: View {
    let memo: VoiceMemo
    let isPlaying: Bool
    let isSelected: Bool
    let isFocused: Bool
    let onPlay: () -> Void
    let onRename: () -> Void
    let onShare: () -> URL
    let onExport: () -> Void
    let onRetranscribe: () -> Void
    let onToggleTranscribe: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 44, height: 44)
                    .background(DesignSystem.Surface.raised)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause memo" : "Play memo")
            .accessibilityValue(VoiceMemoAccessibility.durationValue(memo.durationSeconds))
            .accessibilityHint("Plays audio without changing memo selection")
            .help(isPlaying ? "Pause memo" : "Play memo")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(memo.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(TimeFormatter.formatDuration(memo.durationSeconds))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if memo.isTranscribing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let transcript = memo.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if memo.autoTranscribe {
                    Text("No transcript")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Auto-transcribe off")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                ShareLink(item: onShare()) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(DesignSystem.Text.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share memo")
                .accessibilityHint("Share audio for this memo")
                .help("Share memo")

                Menu {
                    Button("Rename") {
                        onRename()
                    }
                    Button("Export Audio") {
                        onExport()
                    }
                    Button("Re-transcribe") {
                        onRetranscribe()
                    }
                    .disabled(memo.isTranscribing)
                    Button(
                        memo.autoTranscribe ? "Disable Auto-Transcribe" : "Enable Auto-Transcribe"
                    ) {
                        onToggleTranscribe()
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(DesignSystem.Text.secondary)
                        .frame(width: 44, height: 44)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More actions for \(memo.title)")
                .accessibilityHint("Rename, export, transcribe, or delete memo")
                .help("More memo actions")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? DesignSystem.States.active.opacity(0.18) : DesignSystem.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isFocused
                        ? DesignSystem.States.activeBright
                        : (isSelected ? DesignSystem.States.active.opacity(0.7) : DesignSystem.Stroke.subtle),
                    lineWidth: isFocused || isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

}

private enum VoiceMemoDestructiveAction: Identifiable {
    case delete(VoiceMemo)

    var id: UUID {
        switch self {
        case .delete(let memo): return memo.id
        }
    }

    var title: String {
        "Delete Memo?"
    }

    var message: String {
        switch self {
        case .delete(let memo):
            let date = DateFormatter.localizedString(
                from: memo.createdAt,
                dateStyle: .medium,
                timeStyle: .short
            )
            return "This permanently deletes \u{201C}\(memo.title)\u{201D} recorded \(date), including its audio and transcript. This cannot be undone."
        }
    }

    var confirmButtonTitle: String {
        "Delete Memo"
    }
}

private enum VoiceMemoAccessibility {
    static func durationValue(_ duration: TimeInterval) -> String {
        "Duration \(TimeFormatter.formatDuration(duration))"
    }
}

private struct VoiceMemoDetailView: View {
    let memo: VoiceMemo
    @ObservedObject var manager: VoiceMemoManager

    @State private var waveformSamples: [CGFloat] = []
    @State private var isLoadingWaveform = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 12) {
                waveformSection
                playbackControls
            }
            .padding(16)
            .glassCard(cornerRadius: 18)

            transcriptSection

            Spacer(minLength: 0)
        }
        .task(id: memo.id) {
            await loadWaveform()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memo.title)
                .font(.system(size: 20, weight: .semibold))
            Text(formattedDate(memo.createdAt))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var waveformSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if isLoadingWaveform {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            MemoWaveformView(
                samples: waveformSamples,
                progress: playbackProgress,
                isActive: isPlaying
            )
            .frame(height: 110)
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.25))
            .cornerRadius(14)
            .accessibilityHidden(true)
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(DesignSystem.Surface.raised)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause memo" : "Play memo")
                    .accessibilityValue(VoiceMemoAccessibility.durationValue(playbackDuration))
                    .accessibilityHint("Starts or pauses playback")
                    .help(isPlaying ? "Pause memo" : "Play memo")

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: playbackBinding, in: 0...max(playbackDuration, 0.1))
                        .tint(.blue)
                        .accessibilityLabel("Playback position")
                        .accessibilityValue(
                            "\(TimeFormatter.formatDuration(playbackTime)) of \(TimeFormatter.formatDuration(playbackDuration))"
                        )
                        .accessibilityHint("Adjusts memo playback position")
                    HStack {
                        Text(TimeFormatter.formatDuration(playbackTime))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(TimeFormatter.formatDuration(playbackDuration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if memo.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }

                if isPlaying {
                    Text("Playing")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button {
                    manager.retranscribe(memo)
                } label: {
                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(memo.isTranscribing)
                .accessibilityLabel("Re-transcribe memo")
                .accessibilityHint("Replaces current transcript with a new transcription")
                .help("Re-transcribe memo")
            }

            TranscriptHighlightView(
                text: transcriptText,
                words: memo.transcriptWords ?? [],
                isPlaceholder: transcriptIsPlaceholder,
                playbackTime: playbackTime,
                isActive: isPlaying
            )
            .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 240)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private var isPlaying: Bool {
        manager.currentlyPlayingID == memo.id
    }

    private var playbackTime: TimeInterval {
        isPlaying ? manager.playbackTime : 0
    }

    private var playbackDuration: TimeInterval {
        max(manager.playbackDuration, memo.durationSeconds)
    }

    private var playbackProgress: CGFloat {
        guard playbackDuration > 0 else { return 0 }
        return CGFloat(playbackTime / playbackDuration)
    }

    private var playbackBinding: Binding<Double> {
        Binding(
            get: { playbackTime },
            set: { manager.seek(to: $0) }
        )
    }

    private var transcriptText: String {
        if memo.isTranscribing {
            return "Transcribing..."
        }
        if let transcript = memo.transcript, !transcript.isEmpty {
            return transcript
        }
        return memo.autoTranscribe ? "No transcript yet." : "Auto-transcribe is disabled."
    }

    private var transcriptIsPlaceholder: Bool {
        memo.isTranscribing || memo.transcript?.isEmpty != false
    }

    private func togglePlayback() {
        manager.togglePlayback(for: memo)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor
    private func loadWaveform() async {
        isLoadingWaveform = true
        waveformSamples = []
        let url = manager.audioURL(for: memo)

        let samples = await Task.detached {
            guard let audio = try? AudioFileLoader.loadPCM16kMono(from: url) else {
                return [CGFloat]()
            }
            return WaveformSampler.downsample(audio, bars: 120)
        }.value

        await MainActor.run {
            waveformSamples = samples
            isLoadingWaveform = false
        }
    }
}

private struct TranscriptHighlightView: View {
    let text: String
    let words: [TranscriptWord]
    let isPlaceholder: Bool
    let playbackTime: TimeInterval
    let isActive: Bool

    @State private var lastScrolledIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let baseColor = Color.primary.opacity(0.86)
    private let highlightText = Color.primary
    private let highlightBackground = Color.primary.opacity(0.18)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isPlaceholder || words.isEmpty {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    TranscriptFlowLayout(spacing: 6, rowSpacing: 8) {
                        ForEach(words.indices, id: \.self) { index in
                            let word = displayWord(words[index].word)
                            let isHighlighted = index == activeWordIndex

                            Text(word)
                                .font(
                                    .system(size: 14, weight: isHighlighted ? .semibold : .regular)
                                )
                                .foregroundColor(isHighlighted ? highlightText : baseColor)
                                .padding(.horizontal, isHighlighted ? 5 : 0)
                                .padding(.vertical, isHighlighted ? 2 : 0)
                                .background(isHighlighted ? highlightBackground : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
            .onChange(of: activeWordIndex) { _, newValue in
                guard isActive, let index = newValue else { return }
                guard lastScrolledIndex != index else { return }
                lastScrolledIndex = index
                if reduceMotion {
                    proxy.scrollTo(index, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private var activeWordIndex: Int? {
        guard isActive, !words.isEmpty else { return nil }
        let time = playbackTime
        if let exactIndex = words.firstIndex(where: { time >= $0.start && time <= $0.end }) {
            return exactIndex
        }
        return words.lastIndex(where: { time >= $0.start })
    }

    private func displayWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TranscriptFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    init(spacing: CGFloat = 6, rowSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: min(maxWidth, max(0, x - spacing)), height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct MemoWaveformView: View {
    let samples: [CGFloat]
    let progress: CGFloat
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let barWidth = max((proxy.size.width / CGFloat(max(samples.count, 1))) - 2, 2)
            let activeColor = Color(red: 0.62, green: 0.46, blue: 1.0)
            let inactiveColor = Color.white.opacity(0.18)

            HStack(alignment: .center, spacing: 2) {
                ForEach(samples.indices, id: \.self) { index in
                    let level = max(0.04, samples[index])
                    let isFilled = CGFloat(index) / CGFloat(max(samples.count - 1, 1)) <= progress
                    Capsule()
                        .fill(isFilled && isActive ? activeColor : inactiveColor)
                        .frame(width: barWidth, height: level * height)
                        .opacity(isActive ? 1 : 0.6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum WaveformSampler {
    static func downsample(_ samples: [Float], bars: Int) -> [CGFloat] {
        guard !samples.isEmpty, bars > 0 else { return [] }

        let bucketSize = max(samples.count / bars, 1)
        var values: [CGFloat] = []
        values.reserveCapacity(bars)

        var index = 0
        while index < samples.count {
            let end = min(index + bucketSize, samples.count)
            var peak: Float = 0
            for sample in samples[index..<end] {
                peak = max(peak, abs(sample))
            }
            values.append(CGFloat(peak))
            index += bucketSize
        }

        let maxValue = values.max() ?? 0
        guard maxValue > 0 else { return values.map { _ in 0.04 } }
        return values.map { max(0.04, $0 / maxValue) }
    }
}

private struct RecordingWaveform: View {
    let level: Float
    private let barCount = 18

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
        .accessibilityHidden(true)
    }
}
