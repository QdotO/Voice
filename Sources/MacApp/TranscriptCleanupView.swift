import AppKit
import SwiftUI
import WhisperShared

final class TranscriptCleanupViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var suggestedText: String = ""
    @Published var hunks: [TranscriptDiffHunk] = []
    @Published var accepted: Set<UUID> = []
    @Published var isRunning: Bool = false
    @Published var source: String = ""
    @Published var error: String?

    func reset(with text: String? = nil) {
        if let text {
            inputText = text
        }
        suggestedText = ""
        hunks = []
        accepted = []
        isRunning = false
        source = ""
        error = nil
    }

    func setInput(_ text: String) {
        inputText = text
        suggestedText = ""
        hunks = []
        accepted = []
        source = ""
        error = nil
    }

    @MainActor func suggestCleanup(useCopilot: Bool, copilotAnalyzeEndpoint: String) async {
        let original = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        guard !isRunning else { return }

        isRunning = true
        error = nil
        source = ""

        let result = await TranscriptCleanupService.suggestCleanup(
            text: original,
            useCopilot: useCopilot,
            copilotAnalyzeEndpoint: copilotAnalyzeEndpoint
        )

        suggestedText = result.cleanedText
        source = result.source
        error = result.error

        let computed = TranscriptDiff.hunks(original: original, suggested: result.cleanedText)
        hunks = computed
        accepted = Set(computed.filter { $0.isChange }.map { $0.id })

        isRunning = false
    }

    var changeHunks: [TranscriptDiffHunk] {
        hunks.filter { $0.isChange }
    }

    var outputText: String {
        if !hunks.isEmpty {
            return TranscriptDiff.apply(hunks: hunks, accepted: accepted)
        }
        if !suggestedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return suggestedText
        }
        return inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func acceptAll() {
        accepted = Set(changeHunks.map { $0.id })
    }

    func rejectAll() {
        accepted = []
    }

    func toggleAcceptance(_ id: UUID) {
        if accepted.contains(id) {
            accepted.remove(id)
        } else {
            accepted.insert(id)
        }
    }
}

struct TranscriptCleanupView: View {
    @ObservedObject var viewModel: TranscriptCleanupViewModel
    @ObservedObject var voiceMemoManager: VoiceMemoManager
    let openMainWindow: () -> Void

    @AppStorage("useCopilotAnalysis") private var useCopilotAnalysis = false
    @AppStorage("copilotBridgeURL") private var copilotBridgeURL = "http://127.0.0.1:32190/analyze"

    @State private var selectedMemoID: UUID?

    var body: some View {
        ZStack {
            DesignSystem.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                content
            }
            .padding(20)
        }
        .frame(minWidth: 920, minHeight: 640)
        .onAppear {
            if selectedMemoID == nil {
                selectedMemoID = voiceMemoManager.memos.first(where: { ($0.transcript?.isEmpty ?? true) == false })?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                openMainWindow()
            } label: {
                Label("Main Window", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Transcript Cleanup")
                    .font(.system(size: 20, weight: .semibold))
                Text("Review each correction before applying.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Paste") {
                    pasteFromClipboard()
                }
                .buttonStyle(.bordered)

                Button(viewModel.isRunning ? "Cleaning..." : "Suggest Cleanup") {
                    Task { await viewModel.suggestCleanup(useCopilot: useCopilotAnalysis, copilotAnalyzeEndpoint: copilotBridgeURL) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Accept All") {
                    viewModel.acceptAll()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.changeHunks.isEmpty)

                Button("Reject All") {
                    viewModel.rejectAll()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.changeHunks.isEmpty)

                Button("Copy Output") {
                    copyToClipboard(viewModel.outputText)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.outputText.isEmpty)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var content: some View {
        VStack(spacing: 14) {
            sourceRow

            HStack(alignment: .top, spacing: 14) {
                inputPanel
                outputPanel
            }
            .frame(maxHeight: 260)

            changesPanel
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 10) {
            Picker("Load from memo", selection: $selectedMemoID) {
                Text("None").tag(UUID?.none)
                ForEach(voiceMemoManager.memos.filter { ($0.transcript?.isEmpty ?? true) == false }) { memo in
                    Text(memo.title).tag(UUID?.some(memo.id))
                }
            }
            .frame(width: 260)

            Button("Load Transcript") {
                loadSelectedMemo()
            }
            .buttonStyle(.bordered)
            .disabled(selectedMemo == nil)

            Spacer()

            if viewModel.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else if let source = sourceLabel {
                Text(source)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            if let error = viewModel.error, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .help(error)
            }
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.black.opacity(0.2))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output (preview)")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: .constant(viewModel.outputText))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.black.opacity(0.2))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var changesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Corrections")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.changeHunks.count) suggested")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if viewModel.changeHunks.isEmpty {
                Text("No suggested corrections yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(14)
            } else {
                List {
                    ForEach(viewModel.changeHunks) { hunk in
                        CorrectionRow(
                            hunk: hunk,
                            isAccepted: viewModel.accepted.contains(hunk.id),
                            onToggle: { viewModel.toggleAcceptance(hunk.id) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.15))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private var selectedMemo: VoiceMemo? {
        guard let id = selectedMemoID else { return nil }
        return voiceMemoManager.memos.first(where: { $0.id == id })
    }

    private var sourceLabel: String? {
        let value = viewModel.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        return "Source: \(value)"
    }

    private func loadSelectedMemo() {
        guard let memo = selectedMemo, let transcript = memo.transcript else { return }
        viewModel.setInput(transcript)
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let value = pasteboard.string(forType: .string) else { return }
        viewModel.setInput(value)
    }

    private func copyToClipboard(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }
}

private struct CorrectionRow: View {
    let hunk: TranscriptDiffHunk
    let isAccepted: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { isAccepted }, set: { _ in onToggle() })) {
                    Text(labelText)
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)

                Spacer()

                Text(hunk.kind.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            if !hunk.originalText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(hunk.originalText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !hunk.suggestedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(hunk.suggestedText)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(isAccepted ? 0.10 : 0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isAccepted ? 0.18 : 0.10), lineWidth: 1)
        )
    }

    private var labelText: String {
        switch hunk.kind {
        case .modify:
            return "Replace sentence"
        case .replace:
            return "Replace block"
        case .insert:
            return "Insert text"
        case .delete:
            return "Delete text"
        case .equal:
            return "Unchanged"
        }
    }
}
