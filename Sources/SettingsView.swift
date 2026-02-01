import AVFoundation
import AppKit
import HotKey
import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "base.en"
    @AppStorage("showStatusIndicator") private var showStatusIndicator = true
    @AppStorage("usePaste") private var usePaste = false
    @AppStorage("alwaysCopyToClipboard") private var alwaysCopyToClipboard = true
    @AppStorage("useCustomStatusPosition") private var useCustomStatusPosition = false
    @AppStorage("statusOverlayPosition") private var statusOverlayPosition = "topCenter"
    @AppStorage("useCustomWaveColor") private var useCustomWaveColor = false
    @AppStorage("waveColorHex") private var waveColorHex = "#8B5CF6"
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = Int(Key.d.carbonKeyCode)
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = Int(
        NSEvent.ModifierFlags([.command, .shift]).carbonFlags)
    @AppStorage("stopHotkeyKeyCode") private var stopHotkeyKeyCode = Int(Key.s.carbonKeyCode)
    @AppStorage("stopHotkeyModifiers") private var stopHotkeyModifiers = Int(
        NSEvent.ModifierFlags([.command, .option]).carbonFlags)
    @AppStorage("autoStopEnabled") private var autoStopEnabled = true
    @AppStorage("autoStopSilenceSeconds") private var autoStopSilenceSeconds = 1.5
    @AppStorage("recordingMode") private var recordingMode = RecordingMode.hold.rawValue

    @State private var selectedCategory: String?
    @State private var searchText = ""
    @State private var showAddTerm = false
    @State private var newTerm = ""
    @State private var newCategory = "Custom"
    @State private var requestAccessibilityToggle = false

    private let vocab = Vocabulary.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var isRecordingShortcut = false
    @State private var isRecordingStopShortcut = false

    var body: some View {
        ZStack {
            DesignSystem.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Group {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .model:
                        modelTab
                    case .vocabulary:
                        vocabularyTab
                    case .permissions:
                        permissionsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 600, height: 500)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 4)

            Picker("Section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
                .opacity(0.5)
        )
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                Picker("Recording Mode", selection: $recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Activation") {
                    Text("\(activationHint) \(hotkeyDisplay)")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                }
                HStack(spacing: 12) {
                    Text("Start")
                    HotkeyRecorderView(
                        keyCode: $hotkeyKeyCode,
                        modifiers: $hotkeyModifiers,
                        isRecording: $isRecordingShortcut
                    )
                    .frame(width: 200, height: 32)

                    Button(action: { isRecordingShortcut.toggle() }) {
                        Image(
                            systemName: isRecordingShortcut ? "stop.circle.fill" : "record.circle"
                        )
                        .font(.title2)
                        .foregroundColor(isRecordingShortcut ? .red : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button("Reset") {
                        hotkeyKeyCode = Int(Key.d.carbonKeyCode)
                        hotkeyModifiers = Int(
                            NSEvent.ModifierFlags([.command, .shift]).carbonFlags)
                    }
                }

                HStack(spacing: 12) {
                    Text("Stop")
                    HotkeyRecorderView(
                        keyCode: $stopHotkeyKeyCode,
                        modifiers: $stopHotkeyModifiers,
                        isRecording: $isRecordingStopShortcut
                    )
                    .frame(width: 200, height: 32)

                    Button(action: { isRecordingStopShortcut.toggle() }) {
                        Image(
                            systemName: isRecordingStopShortcut
                                ? "stop.circle.fill"
                                : "stop.circle"
                        )
                        .font(.title2)
                        .foregroundColor(isRecordingStopShortcut ? .red : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button("Reset") {
                        stopHotkeyKeyCode = Int(Key.s.carbonKeyCode)
                        stopHotkeyModifiers = Int(
                            NSEvent.ModifierFlags([.command, .option]).carbonFlags)
                    }
                }
                Text("Click Record, then press a shortcut with at least one modifier.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Auto Stop") {
                Toggle("Auto stop on silence", isOn: $autoStopEnabled)

                if autoStopEnabled {
                    HStack {
                        Text("Silence duration")
                        Spacer()
                        Text("\(autoStopSilenceSeconds, specifier: "%.1fs")")
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $autoStopSilenceSeconds, in: 0.5...4.0, step: 0.1)

                    Text("Stops recording automatically when no speech is detected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Output") {
                Toggle("Show status indicator", isOn: $showStatusIndicator)
                Toggle("Use paste instead of typing", isOn: $usePaste)
                Toggle("Always copy transcription to clipboard", isOn: $alwaysCopyToClipboard)
                Text("Paste is faster for long text but briefly uses the clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Appearance") {
                Toggle("Customize status location", isOn: $useCustomStatusPosition)

                if useCustomStatusPosition {
                    Picker("Position", selection: $statusOverlayPosition) {
                        Text("Top Center").tag("topCenter")
                        Text("Top Left").tag("topLeft")
                        Text("Top Right").tag("topRight")
                        Text("Bottom Center").tag("bottomCenter")
                        Text("Bottom Left").tag("bottomLeft")
                        Text("Bottom Right").tag("bottomRight")
                    }
                }

                Toggle("Customize wave color", isOn: $useCustomWaveColor)

                if useCustomWaveColor {
                    ColorPicker("Wave color", selection: waveColorBinding)
                        .frame(maxWidth: 260)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Model Tab

    private var modelTab: some View {
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $selectedModel) {
                    Section("English (Faster)") {
                        Text("Tiny").tag("tiny.en")
                        Text("Base").tag("base.en")
                        Text("Small").tag("small.en")
                    }
                    Section("Multilingual") {
                        Text("Tiny").tag("tiny")
                        Text("Base").tag("base")
                        Text("Small").tag("small")
                        Text("Large v3").tag("large-v3")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    modelDescription
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var modelDescription: some View {
        switch selectedModel {
        case "tiny.en", "tiny":
            Text("Fastest, lowest accuracy. Good for quick notes.")
        case "base.en", "base":
            Text("Balanced speed and accuracy. Recommended for most use.")
        case "small.en", "small":
            Text("Better accuracy, slower. Good for technical content.")
        case "large-v3":
            Text("Best accuracy, slowest. Best for complex vocabulary.")
        default:
            EmptyView()
        }
    }

    private var hotkeyDisplay: String {
        let combo = KeyCombo(
            carbonKeyCode: UInt32(hotkeyKeyCode),
            carbonModifiers: UInt32(hotkeyModifiers)
        )
        let description = combo.description
        return description.isEmpty ? "Unassigned" : description
    }

    private var activationHint: String {
        let mode = RecordingMode(rawValue: recordingMode) ?? .hold
        switch mode {
        case .hold:
            return "Hold"
        case .toggle:
            return "Tap"
        }
    }

    private var stopHotkeyDisplay: String {
        let combo = KeyCombo(
            carbonKeyCode: UInt32(stopHotkeyKeyCode),
            carbonModifiers: UInt32(stopHotkeyModifiers)
        )
        let description = combo.description
        return description.isEmpty ? "Unassigned" : description
    }

    private var waveColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: waveColorHex) ?? Color.purple },
            set: { newValue in
                waveColorHex = newValue.toHexString() ?? "#8B5CF6"
            }
        )
    }

    // MARK: - Vocabulary Tab

    private var vocabularyTab: some View {
        HSplitView {
            // Category list
            VStack(spacing: 0) {
                Text("CATEGORIES")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                List(selection: $selectedCategory) {
                    ForEach(Vocabulary.categories, id: \.self) { category in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor.opacity(0.8))
                            Text(category)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(vocab.terms(in: category).count)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .tag(category)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 160)
            .background(Color.black.opacity(0.2))

            // Terms list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search terms...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .padding(12)

                // Terms
                List {
                    ForEach(filteredTerms) { term in
                        HStack {
                            Toggle(
                                term.term,
                                isOn: Binding(
                                    get: { term.enabled },
                                    set: { _ in vocab.toggle(term) }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .font(.system(.body, design: .monospaced))

                            Spacer()

                            Button(role: .destructive) {
                                vocab.remove(term)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                // Hover effect would go here if we had state for it
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .scrollContentBackground(.hidden)

                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Add term
                HStack {
                    Button(action: { showAddTerm = true }) {
                        Label("Add Term", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    if let category = selectedCategory {
                        Menu {
                            Button("Enable All") {
                                vocab.setCategory(category, enabled: true)
                            }
                            Button("Disable All") {
                                vocab.setCategory(category, enabled: false)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.3))
            }
            .frame(minWidth: 300)
        }
        .sheet(isPresented: $showAddTerm) {
            addTermSheet
        }
    }

    private var filteredTerms: [VocabTerm] {
        var terms = selectedCategory.map { vocab.terms(in: $0) } ?? vocab.allTerms

        if !searchText.isEmpty {
            terms = terms.filter { $0.term.localizedCaseInsensitiveContains(searchText) }
        }

        return terms.sorted { $0.term < $1.term }
    }

    private var addTermSheet: some View {
        VStack(spacing: 20) {
            Text("Add Vocabulary Term")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Term")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter custom term", text: $newTerm)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $newCategory) {
                        ForEach(Vocabulary.categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showAddTerm = false
                    newTerm = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Term") {
                    if !newTerm.isEmpty {
                        vocab.add(newTerm, category: newCategory)
                        newTerm = ""
                        showAddTerm = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTerm.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(DesignSystem.backgroundGradient)
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            Section("Required Permissions") {
                permissionRow(
                    title: "Microphone",
                    description: "Required for voice capture",
                    icon: "mic.fill",
                    isGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    action: {
                        Task {
                            await AVCaptureDevice.requestAccess(for: .audio)
                        }
                    }
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Required for typing into apps",
                    icon: "keyboard.fill",
                    isGranted: TextInjector.isAccessibilityEnabled,
                    action: {
                        TextInjector.requestAccessibility()
                    }
                )

                if !TextInjector.isAccessibilityEnabled {
                    Text(
                        "Tip: If previously granted, try removing the app from System Settings > Privacy > Accessibility, then add it again."
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                }

                Toggle("Re-request Accessibility permission", isOn: $requestAccessibilityToggle)
                    .onChange(of: requestAccessibilityToggle) { value in
                        if value {
                            TextInjector.requestAccessibility()
                            requestAccessibilityToggle = false
                        }
                    }
                    .padding(.top, 8)

                Button("Open Accessibility Settings") {
                    openAccessibilitySettings()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func permissionRow(
        title: String,
        description: String,
        icon: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 30, height: 30)
                .foregroundColor(isGranted ? .green : .red)
                .background(
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else {
                Button("Grant Access") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case model
    case vocabulary
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .model: return "Model"
        case .vocabulary: return "Vocabulary"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .model: return "cpu"
        case .vocabulary: return "text.book.closed"
        case .permissions: return "lock.shield"
        }
    }
}

private enum RecordingMode: String, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold:
            return "Hold"
        case .toggle:
            return "Toggle"
        }
    }
}

#Preview {
    SettingsView()
}

extension Color {
    fileprivate init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6 else { return nil }

        var int: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&int) else { return nil }

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    fileprivate func toHexString() -> String? {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
