import SwiftUI
import WhisperShared

/// Lets a person review one dictation, teach replacements, and keep original history intact.
struct CorrectionLearningEditorView: View {
    let entry: DictationHistoryEntry?
    private let correctionEngine: CorrectionEngine
    private let onSaved: (() -> Void)?

    @State private var editedText: String
    @State private var savedCorrectionCount: Int?

    init(
        entry: DictationHistoryEntry?,
        correctionEngine: CorrectionEngine = .shared,
        onSaved: (() -> Void)? = nil
    ) {
        self.entry = entry
        self.correctionEngine = correctionEngine
        self.onSaved = onSaved
        _editedText = State(initialValue: entry?.text ?? "")
    }

    var body: some View {
        Group {
            if let entry {
                editor(for: entry)
            } else {
                ContentUnavailableView(
                    "Select a dictation",
                    systemImage: "pencil.and.outline",
                    description: Text("Choose a past dictation to review and teach corrections.")
                )
            }
        }
        .onChange(of: entry?.id) { _, _ in
            editedText = entry?.text ?? ""
            savedCorrectionCount = nil
        }
    }

    private func editor(for entry: DictationHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(for: entry)

            HSplitView {
                transcriptPane(
                    title: "Original",
                    text: entry.text,
                    isEditable: false
                )
                .frame(minWidth: 240)

                transcriptPane(
                    title: "Corrected",
                    text: editedText,
                    isEditable: true
                )
                .frame(minWidth: 240)
            }
            .frame(minHeight: 180)

            differencePreview

            HStack {
                if let savedCorrectionCount {
                    Label(
                        "Learned \(savedCorrectionCount) correction\(savedCorrectionCount == 1 ? "" : "s")",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .font(.caption)
                }

                Spacer()

                Button("Reset") {
                    editedText = entry.text
                    savedCorrectionCount = nil
                }
                .disabled(!hasEdits(for: entry))

                Button("Learn Corrections", systemImage: "text.badge.checkmark") {
                    learnCorrections(from: entry)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasEdits(for: entry))
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(for entry: DictationHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Correction Editor")
                .font(.title3.weight(.semibold))
            Text("Edit result. Review detected replacements. Save to improve future dictations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func transcriptPane(title: String, text: String, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isEditable {
                TextEditor(text: $editedText)
                    .font(.body.monospaced())
                    .padding(6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary)
                    }
            } else {
                ScrollView {
                    Text(text)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var differencePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changes to Learn")
                .font(.headline)

            if differences.isEmpty {
                Text(hasChangedText ? "Whole transcript will be learned as one correction." : "Edit corrected transcript to preview learned replacements.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(differences.enumerated()), id: \.offset) { _, difference in
                    HStack(spacing: 8) {
                        Text(difference.original)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(difference.corrected)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var hasChangedText: Bool {
        guard let entry else { return false }
        return hasEdits(for: entry)
    }

    private var differences: [(original: String, corrected: String)] {
        guard let entry, hasEdits(for: entry) else { return [] }
        return correctionEngine.extractDifferences(original: entry.text, corrected: editedText)
    }

    private func hasEdits(for entry: DictationHistoryEntry) -> Bool {
        entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            != editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func learnCorrections(from entry: DictationHistoryEntry) {
        let extracted = differences
        if extracted.isEmpty {
            correctionEngine.learn(
                original: entry.text,
                corrected: editedText,
                suggestVocabulary: false
            )
            savedCorrectionCount = 1
        } else {
            for difference in extracted {
                correctionEngine.learn(original: difference.original, corrected: difference.corrected)
            }
            savedCorrectionCount = extracted.count
        }
        onSaved?()
    }
}
