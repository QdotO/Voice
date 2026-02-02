import SwiftUI
import WhisperShared

struct HistoryView: View {
    @State private var entries: [DictationHistoryEntry] = []
    @State private var searchText = ""
    @State private var methodFilter: HistoryMethodFilter = .all
    private let history = DictationHistory.shared
    private let textInjector = TextInjector()

    var body: some View {
        ZStack {
            DesignSystem.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if entries.isEmpty {
                    emptyState
                } else if filteredEntries.isEmpty {
                    filteredEmptyState
                } else {
                    List(filteredEntries) { entry in
                        HistoryRow(
                            entry: entry,
                            onCopy: { copy(entry) },
                            onPaste: { paste(entry) },
                            onDelete: { history.remove(id: entry.id) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            entries = history.allEntries()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: DictationHistory.didChangeNotification)
        ) { _ in
            entries = history.allEntries()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictation History")
                    .font(.system(size: 20, weight: .semibold))
                Text("Recent transcriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("", selection: $methodFilter) {
                ForEach(HistoryMethodFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
            .frame(width: 180)

            Button(action: { history.clear() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(entries.isEmpty)
            .opacity(entries.isEmpty ? 0.5 : 1)
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
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No dictations yet")
                .font(.headline)
            Text("Start dictating and your results will appear here.")
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

    private func copy(_ entry: DictationHistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    private func paste(_ entry: DictationHistoryEntry) {
        do {
            try textInjector.paste(entry.text)
        } catch {
            copy(entry)
        }
    }
}

private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    let onCopy: () -> Void
    let onPaste: () -> Void
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
        let normalized = outputMethod.lowercased()
        switch self {
        case .all:
            return true
        case .typed:
            return normalized.contains("type")
        case .pasted:
            return normalized.contains("paste")
        case .clipboard:
            return normalized == "clipboard"
        }
    }
}

#Preview {
    HistoryView()
}
