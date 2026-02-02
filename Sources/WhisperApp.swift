import AppKit
import HotKey
import SwiftUI

@main
struct WhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotKey?
    private var stopHotkey: HotKey?
    private var statusWindow: NSWindow?
    private var statusHostingView: NSHostingView<StatusView>?
    private var historyMenu: NSMenu?
    private var historyWindow: NSWindow?
    private var voiceMemosWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var hotkeyMonitor: NSObjectProtocol?
    private var currentHotkeyKeyCode: Int?
    private var currentHotkeyModifiers: Int?
    private var currentStopHotkeyKeyCode: Int?
    private var currentStopHotkeyModifiers: Int?
    private var currentUseCustomStatusPosition: Bool?
    private var currentStatusOverlayPosition: String?

    private let audioCapture = AudioCapture()
    private let transcriber = Transcriber()
    private let voiceMemoTranscriber = Transcriber()
    private let textInjector = TextInjector()
    private let dictationHistory = DictationHistory.shared
    private let statusViewModel = StatusViewModel()
    private lazy var voiceMemoManager = VoiceMemoManager(
        transcriber: voiceMemoTranscriber,
        modelProvider: { [weak self] in
            self?.selectedModel ?? "base.en"
        }
    )
    private var transcriptionTask: Task<Void, Never>?
    private var activeTranscriptionID: UUID?
    private var lastTargetApp: NSRunningApplication?
    private var lastTargetBundleIdentifier: String?
    private var lastVoiceActivityTime: TimeInterval = 0
    private let autoStopLevelThreshold: Float = 0.08

    private var isRecording = false
    private var state: DictationState = .loading {
        didSet { updateUI() }
    }
    private var lastTranscription = "" {
        didSet { updateUI() }
    }

    @AppStorage("selectedModel") private var selectedModel = "base.en"
    @AppStorage("showStatusIndicator") private var showStatusIndicator = true
    @AppStorage("usePaste") private var usePaste = false
    @AppStorage("alwaysCopyToClipboard") private var alwaysCopyToClipboard = true
    @AppStorage("useCustomStatusPosition") private var useCustomStatusPosition = false
    @AppStorage("statusOverlayPosition") private var statusOverlayPosition = "topCenter"
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = Int(Key.d.carbonKeyCode)
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = Int(
        NSEvent.ModifierFlags([.command, .shift]).carbonFlags)
    @AppStorage("stopHotkeyKeyCode") private var stopHotkeyKeyCode = Int(Key.s.carbonKeyCode)
    @AppStorage("stopHotkeyModifiers") private var stopHotkeyModifiers = Int(
        NSEvent.ModifierFlags([.command, .option]).carbonFlags)
    @AppStorage("autoStopEnabled") private var autoStopEnabled = true
    @AppStorage("autoStopSilenceSeconds") private var autoStopSilenceSeconds = 1.5
    @AppStorage("recordingMode") private var recordingMode = "hold"

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.setup()
        setupStatusItem()
        setupHotkey()
        setupStatusWindow()
        setupCallbacks()
        requestPermissionsAndLoad()
    }

    private func setupCallbacks() {
        // Wire up error handlers for debugging
        audioCapture.onError = { error in
            print("[AudioCapture] Error: \(error)")
        }

        audioCapture.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.statusViewModel.level = level
                self?.handleAudioLevel(level)
            }
        }

        transcriber.onError = { error in
            print("[Transcriber] Error: \(error)")
        }

        transcriber.onModelLoaded = { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    print("[Transcriber] Model loaded successfully")
                    self?.state = .ready
                } else {
                    print("[Transcriber] Model failed to load: \(error ?? "unknown")")
                    self?.state = .error(error ?? "Model load failed")
                }
            }
        }
    }

    private func requestPermissionsAndLoad() {
        state = .loading

        // Check accessibility first (needed for hotkey AND text injection)
        if !TextInjector.isAccessibilityEnabled {
            print("[Whisper] Requesting accessibility permission...")
            TextInjector.requestAccessibility()
        }

        // Request microphone and then load model
        Task {
            let hasMic = await audioCapture.requestPermission()
            print("[Whisper] Microphone permission: \(hasMic)")

            if !hasMic {
                await MainActor.run {
                    state = .error("Microphone access denied")
                }
                return
            }

            await MainActor.run {
                loadModel()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform", accessibilityDescription: "Whisper")
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Main Window...", action: #selector(openMainWindow), keyEquivalent: "0"))
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        let voiceMemosItem = NSMenuItem(
            title: "Voice Memos...", action: #selector(openVoiceMemosWindow), keyEquivalent: "m")
        menu.addItem(voiceMemosItem)

        let historyWindowItem = NSMenuItem(
            title: "History...", action: #selector(openHistoryWindow), keyEquivalent: "h")
        menu.addItem(historyWindowItem)

        let historyMenuItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let historySubmenu = NSMenu()
        historyMenuItem.submenu = historySubmenu
        menu.addItem(historyMenuItem)
        historyMenu = historySubmenu
        updateHistoryMenu()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupHotkey() {
        registerHotkey()
        registerStopHotkey()

        hotkeyMonitor = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshHotkeyIfNeeded()
            self?.refreshStatusPositionIfNeeded()
        }
    }

    private func refreshHotkeyIfNeeded() {
        let newKeyCode = hotkeyKeyCode
        let newModifiers = hotkeyModifiers
        let newStopKeyCode = stopHotkeyKeyCode
        let newStopModifiers = stopHotkeyModifiers

        if newKeyCode != currentHotkeyKeyCode || newModifiers != currentHotkeyModifiers {
            registerHotkey()
        }

        if newStopKeyCode != currentStopHotkeyKeyCode
            || newStopModifiers != currentStopHotkeyModifiers
        {
            registerStopHotkey()
        }
    }

    private func refreshStatusPositionIfNeeded() {
        if currentUseCustomStatusPosition == useCustomStatusPosition,
            currentStatusOverlayPosition == statusOverlayPosition
        {
            return
        }

        applyStatusWindowPosition()
    }

    private func currentKeyCombo() -> KeyCombo? {
        guard hotkeyKeyCode > 0 else { return nil }
        return KeyCombo(
            carbonKeyCode: UInt32(hotkeyKeyCode),
            carbonModifiers: UInt32(hotkeyModifiers)
        )
    }

    private func currentStopKeyCombo() -> KeyCombo? {
        guard stopHotkeyKeyCode > 0 else { return nil }
        return KeyCombo(
            carbonKeyCode: UInt32(stopHotkeyKeyCode),
            carbonModifiers: UInt32(stopHotkeyModifiers)
        )
    }

    private func registerHotkey() {
        guard let combo = currentKeyCombo() else {
            hotkey = nil
            return
        }

        currentHotkeyKeyCode = hotkeyKeyCode
        currentHotkeyModifiers = hotkeyModifiers
        hotkey = HotKey(keyCombo: combo)
        print("[Whisper] Hotkey registered: \(combo.description)")

        hotkey?.keyDownHandler = { [weak self] in
            self?.handleStartHotkeyDown()
        }

        hotkey?.keyUpHandler = { [weak self] in
            self?.handleStartHotkeyUp()
        }
    }

    private func registerStopHotkey() {
        guard let combo = currentStopKeyCombo() else {
            stopHotkey = nil
            return
        }

        if let startCombo = currentKeyCombo(), combo == startCombo {
            print("[Whisper] Stop hotkey matches start hotkey; skipping stop registration")
            stopHotkey = nil
            return
        }

        currentStopHotkeyKeyCode = stopHotkeyKeyCode
        currentStopHotkeyModifiers = stopHotkeyModifiers
        stopHotkey = HotKey(keyCombo: combo)
        print("[Whisper] Stop hotkey registered: \(combo.description)")

        stopHotkey?.keyDownHandler = { [weak self] in
            print("[Whisper] Stop hotkey DOWN - stopping recording")
            self?.stopAnyRecording()
        }
    }

    private func setupStatusWindow() {
        let windowSize = NSSize(width: 360, height: 70)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let contentView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        contentView.wantsLayer = true
        window.contentView = contentView

        let hostingView = FixedSizeHostingView(
            rootView: StatusView(
                viewModel: statusViewModel,
                onAbort: { [weak self] in
                    self?.abortTranscription()
                })
        )
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        contentView.addSubview(hostingView)
        statusHostingView = hostingView

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true

        // Position at top center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - (windowSize.width / 2)
            let y = screenFrame.maxY - 80
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        statusWindow = window

        applyStatusWindowPosition()

        if showStatusIndicator {
            window.orderFront(nil)
        }
    }

    private func applyStatusWindowPosition() {
        guard let window = statusWindow, let screen = NSScreen.main else { return }

        let windowSize = window.frame.size
        let screenFrame = screen.visibleFrame
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 80

        let position = useCustomStatusPosition ? statusOverlayPosition : "topCenter"
        let x: CGFloat
        switch position {
        case "topLeft":
            x = screenFrame.minX + horizontalPadding
        case "topRight":
            x = screenFrame.maxX - windowSize.width - horizontalPadding
        case "bottomLeft":
            x = screenFrame.minX + horizontalPadding
        case "bottomRight":
            x = screenFrame.maxX - windowSize.width - horizontalPadding
        default:
            x = screenFrame.midX - (windowSize.width / 2)
        }

        let y: CGFloat
        switch position {
        case "bottomLeft", "bottomCenter", "bottomRight":
            y = screenFrame.minY + verticalPadding
        default:
            y = screenFrame.maxY - verticalPadding
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))

        currentUseCustomStatusPosition = useCustomStatusPosition
        currentStatusOverlayPosition = statusOverlayPosition
    }

    private func setupSettingsWindow() {
        setupSettingsWindow(initialTab: .general)
    }

    private func setupSettingsWindow(initialTab: SettingsTab) {
        if let window = settingsWindow {
            window.contentView = NSHostingView(rootView: SettingsView(initialTab: initialTab))
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView(initialTab: initialTab))
        let windowSize = NSSize(width: 600, height: 500)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = hostingView
        window.setContentSize(windowSize)
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
    }

    private func setupHistoryWindow() {
        if historyWindow != nil { return }

        let hostingView = NSHostingView(rootView: HistoryView())
        let windowSize = NSSize(width: 600, height: 450)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictation History"
        window.contentView = hostingView
        window.setContentSize(windowSize)
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize
        window.isReleasedWhenClosed = false
        window.center()
        historyWindow = window
    }

    private func setupVoiceMemosWindow() {
        if voiceMemosWindow != nil { return }

        let hostingView = NSHostingView(rootView: VoiceMemosView(manager: voiceMemoManager))
        let windowSize = NSSize(width: 720, height: 500)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Memos"
        window.contentView = hostingView
        window.setContentSize(windowSize)
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize
        window.isReleasedWhenClosed = false
        window.center()
        voiceMemosWindow = window
    }

    private func setupMainWindow() {
        if mainWindow != nil { return }

        let view = MainView(
            voiceMemoManager: voiceMemoManager,
            statusViewModel: statusViewModel,
            startDictation: { [weak self] in self?.startRecording() },
            stopDictation: { [weak self] in self?.stopRecording() },
            openSettings: { [weak self] in self?.openSettings() },
            openHistory: { [weak self] in self?.openHistoryWindow() },
            openVoiceMemos: { [weak self] in self?.openVoiceMemosWindow() },
            openVocabulary: { [weak self] in self?.openSettingsTab(.vocabulary) }
        )
        let hostingView = NSHostingView(rootView: view)
        let windowSize = NSSize(width: 760, height: 520)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Whisper"
        window.contentView = hostingView
        window.setContentSize(windowSize)
        window.contentMinSize = windowSize
        window.isReleasedWhenClosed = false
        window.center()
        mainWindow = window
    }

    private func loadModel() {
        state = .loading
        print("[Whisper] Loading model: \(selectedModel)")

        // Update vocabulary prompt
        transcriber.vocabularyPrompt = Vocabulary.shared.generatePrompt()

        Task {
            await transcriber.loadModel(selectedModel)
            // Note: state transition now handled by onModelLoaded callback
        }
    }

    // MARK: - Recording

    private func startRecording() {
        print("[Whisper] startRecording called - state: \(state), isRecording: \(isRecording)")

        guard case .ready = state else {
            print("[Whisper] Cannot record - not in ready state")
            return
        }
        guard !isRecording else {
            print("[Whisper] Cannot record - already recording")
            return
        }
        guard !voiceMemoManager.isRecording else {
            print("[Whisper] Cannot record - voice memo session active")
            return
        }

        do {
            captureTargetApp()
            try audioCapture.start()
            isRecording = true
            lastVoiceActivityTime = Date().timeIntervalSinceReferenceDate
            state = .recording
            print("[Whisper] Recording started")
        } catch {
            print("[Whisper] Failed to start recording: \(error)")
            state = .error(error.localizedDescription)
        }
    }

    private func stopRecording() {
        print("[Whisper] stopRecording called - isRecording: \(isRecording)")

        guard isRecording else {
            print("[Whisper] Cannot stop - not recording")
            return
        }

        isRecording = false
        statusViewModel.level = 0
        state = .processing

        let audio = audioCapture.stop()
        let duration = Float(audio.count) / 16000.0
        print("[Whisper] Captured \(audio.count) samples (\(duration)s)")

        guard !audio.isEmpty else {
            print("[Whisper] No audio captured!")
            state = .ready
            return
        }

        // Need minimum audio length for Whisper
        guard audio.count >= 8000 else {
            print("[Whisper] Audio too short (< 0.5s), skipping transcription")
            lastTranscription = "(too short)"
            state = .ready
            return
        }

        let transcriptionID = UUID()
        activeTranscriptionID = transcriptionID
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            print("[Whisper] Starting transcription...")

            // Transcribe
            guard let payload = await transcriber.transcribe(audio) else {
                print("[Whisper] Transcription returned nil")
                await MainActor.run {
                    lastTranscription = "(no speech detected)"
                    state = .ready
                }
                return
            }

            if Task.isCancelled || activeTranscriptionID != transcriptionID {
                return
            }

            print("[Whisper] Raw transcription: '\(payload.text)'")

            // Apply learned corrections
            let finalText = CorrectionEngine.shared.apply(to: payload.text)
            print("[Whisper] Final text: '\(finalText)'")

            await MainActor.run {
                if self.activeTranscriptionID == transcriptionID {
                    self.activateTargetApp()
                }
            }

            try? await Task.sleep(nanoseconds: 80_000_000)

            await MainActor.run { [finalText] in
                guard self.activeTranscriptionID == transcriptionID, !Task.isCancelled else {
                    return
                }
                if alwaysCopyToClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalText, forType: .string)
                }

                // Then type or paste at the cursor
                do {
                    let shouldForceAX = shouldForceAXInsertForTarget()
                    let shouldPaste = usePaste || shouldForcePasteForTarget()

                    if shouldForceAX {
                        print("[Whisper] AX inserting text...")
                        let axInserted =
                            (try? textInjector.insertIntoFocusedElementAdvanced(finalText)) ?? false
                        if axInserted {
                            dictationHistory.addEntry(
                                text: finalText,
                                durationSeconds: Double(duration),
                                model: selectedModel,
                                outputMethod: alwaysCopyToClipboard ? "ax+clipboard" : "ax"
                            )
                        } else {
                            print("[Whisper] AX insert failed, falling back to paste")
                            try textInjector.paste(finalText)
                            dictationHistory.addEntry(
                                text: finalText,
                                durationSeconds: Double(duration),
                                model: selectedModel,
                                outputMethod: alwaysCopyToClipboard ? "paste+clipboard" : "paste"
                            )
                        }
                    } else if shouldPaste {
                        print("[Whisper] Pasting text...")
                        try textInjector.paste(finalText)
                        dictationHistory.addEntry(
                            text: finalText,
                            durationSeconds: Double(duration),
                            model: selectedModel,
                            outputMethod: alwaysCopyToClipboard ? "paste+clipboard" : "paste"
                        )
                    } else {
                        print("[Whisper] Typing text...")
                        try textInjector.type(finalText)
                        dictationHistory.addEntry(
                            text: finalText,
                            durationSeconds: Double(duration),
                            model: selectedModel,
                            outputMethod: alwaysCopyToClipboard ? "type+clipboard" : "type"
                        )
                    }
                    lastTranscription = finalText
                    print("[Whisper] Text injected successfully")
                } catch {
                    print("[Whisper] Text injection failed: \(error)")
                    if let injectionError = error as? TextInjector.InjectionError,
                        injectionError == .accessibilityNotEnabled
                    {
                        TextInjector.requestAccessibility()
                    }

                    let debugMessage = error.localizedDescription
                    let combined =
                        "\(finalText)\n\n[Injection error] \(debugMessage)\n[Hint] Enable Accessibility for Whisper in System Settings > Privacy & Security > Accessibility."
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(combined, forType: .string)
                    lastTranscription = "Copied: \(finalText)"
                    dictationHistory.addEntry(
                        text: finalText,
                        durationSeconds: Double(duration),
                        model: selectedModel,
                        outputMethod: "clipboard"
                    )
                }

                if self.activeTranscriptionID == transcriptionID {
                    state = .ready
                    updateHistoryMenu()
                }
            }
        }
    }

    private func abortTranscription() {
        guard case .processing = state else { return }
        print("[Whisper] Aborting transcription")
        activeTranscriptionID = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        state = .ready
        statusViewModel.level = 0
    }

    private func handleAudioLevel(_ level: Float) {
        guard isRecording, autoStopEnabled else { return }
        let now = Date().timeIntervalSinceReferenceDate

        if level >= autoStopLevelThreshold {
            lastVoiceActivityTime = now
            return
        }

        if now - lastVoiceActivityTime >= autoStopSilenceSeconds {
            print("[Whisper] Auto-stop triggered (silence)")
            stopRecording()
        }
    }

    private func handleStartHotkeyDown() {
        if recordingMode == "toggle" {
            if isRecording {
                print("[Whisper] Hotkey DOWN - toggling stop")
                stopRecording()
            } else {
                print("[Whisper] Hotkey DOWN - toggling start")
                startRecording()
            }
        } else {
            print("[Whisper] Hotkey DOWN - starting recording")
            startRecording()
        }
    }

    private func handleStartHotkeyUp() {
        if recordingMode == "hold" {
            print("[Whisper] Hotkey UP - stopping recording")
            stopRecording()
        }
    }

    private func captureTargetApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        lastTargetApp = frontmost
        lastTargetBundleIdentifier = frontmost.bundleIdentifier
    }

    private func activateTargetApp() {
        guard let app = lastTargetApp, !app.isTerminated else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func shouldForcePasteForTarget() -> Bool {
        let bundleID = lastTargetBundleIdentifier ?? lastTargetApp?.bundleIdentifier
        let name = lastTargetApp?.localizedName ?? ""
        let bundleIDs: Set<String> = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCodeInsiders2",
            "com.vscodium",
        ]

        if let bundleID, bundleIDs.contains(bundleID) {
            return true
        }

        if name.localizedCaseInsensitiveContains("Visual Studio Code - Insiders") {
            return true
        }

        if name.localizedCaseInsensitiveContains("VS Code Insiders") {
            return true
        }

        return false
    }

    private func shouldForceAXInsertForTarget() -> Bool {
        let bundleID = lastTargetBundleIdentifier ?? lastTargetApp?.bundleIdentifier
        let name = lastTargetApp?.localizedName ?? ""
        let bundleIDs: Set<String> = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCodeInsiders2",
            "com.vscodium",
        ]

        if let bundleID, bundleIDs.contains(bundleID) {
            return true
        }

        if name.localizedCaseInsensitiveContains("Visual Studio Code - Insiders") {
            return true
        }

        if name.localizedCaseInsensitiveContains("VS Code Insiders") {
            return true
        }

        return false
    }

    // MARK: - UI Updates

    private func updateUI() {
        statusViewModel.state = state
        statusViewModel.lastText = lastTranscription

        // Update menu bar icon
        let iconName: String
        switch state {
        case .loading:
            iconName = "arrow.down.circle"
        case .ready:
            iconName = "waveform"
        case .recording:
            iconName = "waveform.circle.fill"
        case .processing:
            iconName = "ellipsis.circle"
        case .error:
            iconName = "exclamationmark.triangle"
        }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Whisper")
        }

        // Update status window
        if let window = statusWindow {
            if showStatusIndicator {
                window.orderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }
    }

    private func updateHistoryMenu() {
        guard let historyMenu = historyMenu else { return }

        historyMenu.removeAllItems()

        let entries = dictationHistory.allEntries()
        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No history yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            for entry in entries.prefix(10) {
                let title = historyTitle(for: entry)
                let item = NSMenuItem(
                    title: title, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                item.representedObject = entry.id
                historyMenu.addItem(item)
            }

            historyMenu.addItem(NSMenuItem.separator())
            historyMenu.addItem(
                NSMenuItem(
                    title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        }
    }

    private func historyTitle(for entry: DictationHistoryEntry) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        let time = dateFormatter.string(from: entry.timestamp)
        let snippet = entry.text.prefix(48)
        let ellipsis = entry.text.count > 48 ? "…" : ""
        return "\(time) — \(snippet)\(ellipsis)"
    }

    // MARK: - Actions

    @objc private func openSettings() {
        setupSettingsWindow(initialTab: .general)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsTab(_ tab: SettingsTab) {
        setupSettingsWindow(initialTab: tab)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHistoryWindow() {
        setupHistoryWindow()
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openMainWindow() {
        setupMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openVoiceMemosWindow() {
        setupVoiceMemosWindow()
        voiceMemosWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
            let entry = dictationHistory.entry(id: id)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        lastTranscription = "Copied: \(entry.text)"
        updateUI()
    }

    @objc private func clearHistory() {
        dictationHistory.clear()
        updateHistoryMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func stopAnyRecording() {
        if voiceMemoManager.isRecording {
            voiceMemoManager.stopRecording()
            return
        }

        stopRecording()
    }
}

private final class FixedSizeHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 70)
    }
}
