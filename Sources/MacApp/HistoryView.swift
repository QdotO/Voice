import SwiftUI
import WhisperShared

struct HistoryView: View {
    @State private var entries: [DictationHistoryEntry] = []
    @State private var corrections: [CorrectionRecord] = []
    @State private var searchText = ""
    @State private var methodFilter: HistoryMethodFilter = .all
    @State private var selectedTab: HistorySurfaceTab = .history
    @State private var correctionEntry: DictationHistoryEntry?

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
        .frame(width: 680, height: 500)
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("History & Corrections")
                    .font(.system(size: 20, weight: .semibold))
                Text(selectedTab.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("Surface", selection: $selectedTab) {
                ForEach(HistorySurfaceTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if selectedTab == .history {
                Picker("", selection: $methodFilter) {
                    ForEach(HistoryMethodFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(selectedTab.searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
            .frame(width: 200)

            Button(action: clearActiveSurface) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(isActiveCollectionEmpty)
            .opacity(isActiveCollectionEmpty ? 0.5 : 1)
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

    private var historyList: some View {
        List(filteredEntries) { entry in
            HistoryRow(
                entry: entry,
                onCopy: { copy(entry) },
                onPaste: { paste(entry) },
                onCorrect: { correctionEntry = entry },
                onDelete: { history.remove(id: entry.id) }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var correctionList: some View {
        List(filteredCorrections) { correction in
            LearnedCorrectionRow(
                correction: correction,
                onCopy: { copy(correction.correctedText) },
                onDelete: { correctionEngine.removeCorrection(id: correction.id) }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
            history.clear()
        case .corrections:
            correctionEngine.clearCorrections()
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func copy(_ entry: DictationHistoryEntry) {
        copy(entry.text)
    }

    private func paste(_ entry: DictationHistoryEntry) {
        Task {
            do {
                _ = try await textInsertionService.insert(
                    TextInsertionRequest(text: entry.text, preserveClipboard: true)
                )
            } catch {
                copy(entry)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCorrect: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

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

            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")

                    Button(action: onPaste) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Paste into active app")

                    Button(action: onCorrect) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Correct and teach")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .background(Color.red.opacity(0.2))
                            .clipShape(Circle())
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete entry")
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHovering ? 0.2 : 0.05), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
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
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

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

            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy corrected text")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .background(Color.red.opacity(0.2))
                            .clipShape(Circle())
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete correction")
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHovering ? 0.2 : 0.05), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
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
