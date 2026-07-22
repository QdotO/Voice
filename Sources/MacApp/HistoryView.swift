import AppKit
import SwiftUI
import WhisperShared

struct HistoryView: View {
    @State private var entries: [DictationHistoryEntry] = []
    @State private var corrections: [CorrectionRecord] = []
    @State private var searchText = ""
    @State private var methodFilter: HistoryMethodFilter = .all
    @State private var selectedTab: HistorySurfaceTab = .history
    @State private var correctionEntry: DictationHistoryEntry?
    @State private var selectedHistoryIDs = Set<UUID>()
    @State private var selectedCorrectionIDs = Set<UUID>()
    @State private var pendingDestructiveAction: HistoryDestructiveAction?

    private let history = DictationHistory.shared
    private let correctionEngine = CorrectionEngine.shared
    private let textInsertionService = SystemTextInsertionService.make()

    var body: some View {
        ZStack {
            DesignSystem.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isActiveCollectionEmpty {
                    emptyState
                } else if isFilteredCollectionEmpty {
                    filteredEmptyState
                } else if selectedTab == .history {
                    historyList
                } else {
                    correctionList
                }
            }
        }
        .frame(
            minWidth: WhisperWindowLayout.historyMinimum.width,
            minHeight: WhisperWindowLayout.historyMinimum.height
        )
        .onAppear(perform: refresh)
        .onReceive(
            NotificationCenter.default.publisher(for: DictationHistory.didChangeNotification)
        ) { _ in
            entries = history.allEntries()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: CorrectionEngine.didChangeNotification)
        ) { _ in
            corrections = correctionEngine.allCorrections()
        }
        .sheet(item: $correctionEntry) { entry in
            CorrectionLearningEditorView(entry: entry, onSaved: {
                corrections = correctionEngine.allCorrections()
            })
            .frame(minWidth: 620, minHeight: 430)
        }
        .alert(item: $pendingDestructiveAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.confirmButtonTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                headerTitle
                Spacer()
                surfacePicker
                methodPicker
                searchField
                    .frame(width: 200)
                clearButton
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    headerTitle
                    Spacer()
                    clearButton
                }

                HStack(spacing: 8) {
                    surfacePicker
                        .frame(maxWidth: .infinity)
                    methodPicker
                }

                searchField
                    .frame(maxWidth: .infinity)
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

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("History & Corrections")
                .font(.system(size: 20, weight: .semibold))
            Text(selectedTab.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var surfacePicker: some View {
        Picker("Surface", selection: $selectedTab) {
            ForEach(HistorySurfaceTab.allCases, id: \.self) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }

    @ViewBuilder
    private var methodPicker: some View {
        if selectedTab == .history {
            Picker("", selection: $methodFilter) {
                ForEach(HistoryMethodFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 140)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(selectedTab.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(6)
        .background(Color.white.opacity(0.1))
        .cornerRadius(6)
    }

    private var clearButton: some View {
        Button(action: clearActiveSurface) {
            Image(systemName: "trash")
        }
        .buttonStyle(.whisperIconButton(isDestructive: true))
        .disabled(isActiveCollectionEmpty)
        .opacity(isActiveCollectionEmpty ? 0.5 : 1)
        .accessibilityLabel(selectedTab == .history ? "Clear all History" : "Clear all Corrections")
        .accessibilityHint("Opens confirmation before removing all items")
        .help(selectedTab == .history ? "Clear history" : "Clear corrections")
    }

    private var historyList: some View {
        List(selection: $selectedHistoryIDs) {
            ForEach(filteredEntries) { entry in
                HistoryRow(
                    entry: entry,
                    isSelected: selectedHistoryIDs.contains(entry.id),
                    onCopy: { copy(entry) },
                    onPaste: { paste(entry) },
                    onCorrect: { correctionEntry = entry },
                    onDelete: { requestDeleteHistory(ids: [entry.id]) }
                )
                .tag(entry.id)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onDeleteCommand(perform: requestDeleteSelected)
    }

    private var correctionList: some View {
        List(selection: $selectedCorrectionIDs) {
            ForEach(filteredCorrections) { correction in
                LearnedCorrectionRow(
                    correction: correction,
                    isSelected: selectedCorrectionIDs.contains(correction.id),
                    onCopy: { copy(correction.correctedText) },
                    onDelete: { requestDeleteCorrections(ids: [correction.id]) }
                )
                .tag(correction.id)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onDeleteCommand(perform: requestDeleteSelected)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedTab.emptyIconName)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(selectedTab.emptyTitle)
                .font(.headline)
            Text(selectedTab.emptyMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No matches")
                .font(.headline)
            Text("Try a different search or filter.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEntries: [DictationHistoryEntry] {
        let filteredByMethod = entries.filter { entry in
            methodFilter.matches(entry.outputMethod)
        }

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return filteredByMethod
        }

        let query = searchText.lowercased()
        return filteredByMethod.filter { entry in
            entry.text.lowercased().contains(query) || entry.model.lowercased().contains(query)
                || entry.outputMethod.lowercased().contains(query)
        }
    }

    private var filteredCorrections: [CorrectionRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return corrections
        }

        let query = searchText.lowercased()
        return corrections.filter { correction in
            correction.originalText.lowercased().contains(query)
                || correction.correctedText.lowercased().contains(query)
        }
    }

    private var isActiveCollectionEmpty: Bool {
        switch selectedTab {
        case .history:
            return entries.isEmpty
        case .corrections:
            return corrections.isEmpty
        }
    }

    private var isFilteredCollectionEmpty: Bool {
        switch selectedTab {
        case .history:
            return filteredEntries.isEmpty
        case .corrections:
            return filteredCorrections.isEmpty
        }
    }

    private func refresh() {
        entries = history.allEntries()
        corrections = correctionEngine.allCorrections()
    }

    private func clearActiveSurface() {
        switch selectedTab {
        case .history:
            guard !entries.isEmpty else { return }
            pendingDestructiveAction = .clearHistory(count: entries.count)
        case .corrections:
            guard !corrections.isEmpty else { return }
            pendingDestructiveAction = .clearCorrections(count: corrections.count)
        }
    }

    private func requestDeleteSelected() {
        switch selectedTab {
        case .history:
            requestDeleteHistory(ids: selectedHistoryIDs)
        case .corrections:
            requestDeleteCorrections(ids: Array(selectedCorrectionIDs))
        }
    }

    private func requestDeleteHistory(ids: Set<UUID>) {
        requestDeleteHistory(ids: Array(ids))
    }

    private func requestDeleteHistory(ids: [UUID]) {
        let validIDs = ids.filter { id in entries.contains { $0.id == id } }
        guard !validIDs.isEmpty else { return }
        pendingDestructiveAction = .deleteTranscriptions(ids: validIDs)
    }

    private func requestDeleteCorrections(ids: [UUID]) {
        let validIDs = ids.filter { id in corrections.contains { $0.id == id } }
        guard !validIDs.isEmpty else { return }
        pendingDestructiveAction = .deleteCorrections(ids: validIDs)
    }

    private func perform(_ action: HistoryDestructiveAction) {
        switch action {
        case .deleteTranscriptions(let ids):
            ids.forEach { history.remove(id: $0) }
            selectedHistoryIDs.subtract(ids)
        case .deleteCorrections(let ids):
            ids.forEach { correctionEngine.removeCorrection(id: $0) }
            selectedCorrectionIDs.subtract(ids)
        case .clearHistory:
            history.clear()
            selectedHistoryIDs.removeAll()
        case .clearCorrections:
            correctionEngine.clearCorrections()
            selectedCorrectionIDs.removeAll()
        }
    }

    private func copy(_ value: String, announcement: String = "Copied text to clipboard") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        announce(announcement)
    }

    private func copy(
        _ entry: DictationHistoryEntry,
        announcement: String = "Copied text to clipboard"
    ) {
        copy(entry.text, announcement: announcement)
    }

    private func paste(_ entry: DictationHistoryEntry) {
        Task {
            do {
                _ = try await textInsertionService.insert(
                    TextInsertionRequest(text: entry.text, preserveClipboard: true)
                )
                announce("Pasted transcription into active app")
            } catch {
                copy(entry, announcement: "Could not paste. Copied transcription to clipboard instead")
            }
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }
}

private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    let isSelected: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCorrect: () -> Void
    let onDelete: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(timeString(entry.timestamp))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue.opacity(0.8))
                        .cornerRadius(4)

                    Text(metaString(entry))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            if isSelected {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    .buttonStyle(.whisperIconButton())
                    .keyboardShortcut("c", modifiers: .command)
                    .accessibilityLabel("Copy transcription")
                    .accessibilityHint("Copies selected transcription to clipboard")
                    .help("Copy to clipboard")

                    Button(action: onCorrect) {
                        Image(systemName: "pencil.and.outline")
                    }
                    .buttonStyle(.whisperIconButton())
                    .accessibilityLabel("Correct transcription")
                    .accessibilityHint("Opens correction editor for selected transcription")
                    .help("Correct and teach")
                }
            }

            Menu {
                Button(action: onCopy) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc.fill")
                }
                Button(action: onPaste) {
                    Label("Paste into Active App", systemImage: "arrow.down.doc.fill")
                }
                Button(action: onCorrect) {
                    Label("Correct and Teach", systemImage: "pencil.and.outline")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Transcription", systemImage: "trash.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.whisperIconButton())
            .accessibilityLabel("More transcription actions")
            .accessibilityHint("Opens copy, paste, correct, and delete actions")
            .help("More transcription actions")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? DesignSystem.Stroke.strong : DesignSystem.Stroke.subtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func metaString(_ entry: DictationHistoryEntry) -> String {
        let duration = String(format: "%.1fs", entry.durationSeconds)
        let method = entry.outputMethod.replacingOccurrences(of: "+clipboard", with: "")
        return "\(duration) • \(entry.model) • \(method)"
    }
}

private struct LearnedCorrectionRow: View {
    let correction: CorrectionRecord
    let isSelected: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(timeString(correction.createdAt))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green.opacity(0.85))
                        .cornerRadius(4)

                    if correction.appliedCount > 0 {
                        Text("\(correction.appliedCount)x")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(correction.correctedText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("from: \(correction.originalText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSelected {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    .buttonStyle(.whisperIconButton())
                    .keyboardShortcut("c", modifiers: .command)
                    .accessibilityLabel("Copy learned correction")
                    .accessibilityHint("Copies corrected text to clipboard")
                    .help("Copy corrected text")
                }
            }

            Menu {
                Button(action: onCopy) {
                    Label("Copy Corrected Text", systemImage: "doc.on.doc.fill")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Learned Correction", systemImage: "trash.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.whisperIconButton())
            .accessibilityLabel("More correction actions")
            .accessibilityHint("Opens copy and delete actions")
            .help("More correction actions")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? DesignSystem.Stroke.strong : DesignSystem.Stroke.subtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum HistorySurfaceTab: CaseIterable {
    case history
    case corrections

    var label: String {
        switch self {
        case .history:
            return "History"
        case .corrections:
            return "Corrections"
        }
    }

    var subtitle: String {
        switch self {
        case .history:
            return "Recent transcriptions and insertion history"
        case .corrections:
            return "Learned replacements used to improve final text"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .history:
            return "Search history"
        case .corrections:
            return "Search corrections"
        }
    }

    var emptyIconName: String {
        switch self {
        case .history:
            return "clock.arrow.circlepath"
        case .corrections:
            return "text.badge.checkmark"
        }
    }

    var emptyTitle: String {
        switch self {
        case .history:
            return "No dictations yet"
        case .corrections:
            return "No learned corrections yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .history:
            return "Start dictating and your results will appear here."
        case .corrections:
            return "Corrections are learned from accepted edits and will appear here once available."
        }
    }
}

private enum HistoryMethodFilter: CaseIterable {
    case all
    case typed
    case pasted
    case clipboard

    var label: String {
        switch self {
        case .all: return "All"
        case .typed: return "Typed"
        case .pasted: return "Pasted"
        case .clipboard: return "Clipboard"
        }
    }

    func matches(_ outputMethod: String) -> Bool {
        switch self {
        case .all:
            return true
        case .typed:
            return outputMethod.contains("type")
        case .pasted:
            return outputMethod.contains("paste") || outputMethod.contains("ax")
        case .clipboard:
            return outputMethod.contains("clipboard")
        }
    }
}

#Preview {
    HistoryView()
}
