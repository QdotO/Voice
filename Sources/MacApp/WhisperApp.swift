import AppKit
import HotKey
import OSLog
import SwiftUI
import WhisperShared

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
    private enum DictationTrigger: String {
        case hotkey
        case capsLock
        case ui
    }

    private enum OutputMethod {
        case ax
        case paste
        case type
        case clipboard

        func value(withClipboard: Bool) -> String {
            switch self {
            case .ax:
                return withClipboard ? "ax+clipboard" : "ax"
            case .paste:
                return withClipboard ? "paste+clipboard" : "paste"
            case .type:
                return withClipboard ? "type+clipboard" : "type"
            case .clipboard:
                return "clipboard"
            }
        }
    }

    private var statusItem: NSStatusItem!
    private var hotkey: HotKey?
    private var stopHotkey: HotKey?
    private var menuBarOnlyHotkey: HotKey?
    private var statusWindow: NSWindow?
    private var statusHostingView: NSHostingView<StatusView>?
    private var menuBarOnlyItem: NSMenuItem?
    private var historyMenu: NSMenu?
    private var historyWindow: NSWindow?
    private var voiceMemosWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var immersiveModeWindow: NSWindow?
    private var immersiveModeMenuItem: NSMenuItem?
    private var processingBarWindow: NSWindow?
    private var hotkeyMonitor: NSObjectProtocol?
    private var capsLockEventTap: CFMachPort?
    private var capsLockRunLoopSource: CFRunLoopSource?
    private var capsLockDictationPolicy = CapsLockDictationPolicy()
    private var currentHotkeyKeyCode: Int?
    private var currentHotkeyModifiers: Int?
    private var currentStopHotkeyKeyCode: Int?
    private var currentStopHotkeyModifiers: Int?
    private var currentUseCustomStatusPosition: Bool?
    private var currentStatusOverlayPosition: String?
    private let logger = Logger(subsystem: "Whisper", category: "AppDelegate")

    private let dictationHistory = DictationHistory.shared
    private let statusViewModel = StatusViewModel()
    private let textInsertionService = SystemTextInsertionService.make()
    private lazy var liveWhisperEngine: LiveWhisperEngine = {
        LiveWhisperEngine(audioLevelHandler: { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusViewModel.level = level
                self.handleAudioLevel(level)
            }
        })
    }()
    private lazy var dictationSettingsStore = LegacyAppPreferencesSettingsStore()
    private let promptProvider = DefaultTranscriptionPromptProvider.live()
    private lazy var dictationCoordinator = DefaultDictationCoordinator(
        engine: liveWhisperEngine,
        settingsStore: dictationSettingsStore,
        promptProvider: { [promptProvider] in
            await promptProvider.makePrompt()
        }
    )
    private lazy var voiceMemoManager = VoiceMemoManager(
        engine: liveWhisperEngine,
        settingsStore: dictationSettingsStore,
        promptProvider: { [promptProvider] in
            await promptProvider.makePrompt()
        }
    )
    private var dictationTask: Task<Void, Never>?
    private var preparedModelName: String?
    private var lastTargetApp: NSRunningApplication?
    private var lastTargetBundleIdentifier: String?
    private var lastVoiceActivityTime: TimeInterval = 0
    private var lastPartialUpdateTime: TimeInterval = 0
    private var smoothedNoiseFloor: Float = 0
    private var hasNoiseFloorEstimate = false
    private var recordingStartTime: TimeInterval = 0
    private var latestSessionPartialTranscript = ""
    private var maxObservedAudioLevel: Float = 0
    private var pendingStopTask: Task<Void, Never>?
    private let minimumCaptureDurationForStop: TimeInterval = 1.15
    private let autoStopLevelThreshold: Float = 0.04
    private let autoStopRelativeSpeechDelta: Float = 0.018
    private let autoStopNoSpeechTimeout: TimeInterval = 8.0
    private let autoStopTrailingPartialGrace: TimeInterval = 0.42
    private var hasRecordedInitialReadyMetric = false
    private var hasCompletedHotkeyMetric = false
    private var hasMarkedSpeechStartMetric = false
    private var hasCompletedSpeechPartialMetric = false

    private var isRecording = false
    private var state: DictationState = .loading {
        didSet { updateUI() }
    }
    private var lastTranscription = "" {
        didSet { updateUI() }
    }

    @AppStorage("selectedModel") private var selectedModel = "base.en"
    @AppStorage("showStatusIndicator") private var showStatusIndicator = true
    @AppStorage("menuBarOnlyMode") private var menuBarOnlyMode = false
    @AppStorage("immersiveModeEnabled") private var immersiveModeEnabled = false
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
    @AppStorage("autoStopSilenceSeconds") private var autoStopSilenceSeconds = 1.44
    @AppStorage("recordingMode") private var recordingMode = "hold"
    @AppStorage("enableCapsLockHoldToDictate") private var enableCapsLockHoldToDictate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.setup()
        setupStatusItem()
        setupHotkey()
        setupStatusWindow()
        markMetric(.launchToReady, context: ["model": currentPreparation().resolvedModelName])
        requestPermissionsAndLoad()
    }

    private func requestPermissionsAndLoad() {
        state = .loading

        if !TextInjector.isAccessibilityEnabled {
            logger.info("Requesting accessibility permission")
            TextInjector.requestAccessibility()
        }

        prewarmDictationEngine(force: true)
    }

    private func currentPreparation() -> WhisperEnginePreparation {
        let settings = dictationSettingsStore.load()
        return WhisperEnginePreparation(
            profile: settings.selectedProfile,
            rawModelOverride: settings.rawModelOverride
        )
    }

    private func prewarmDictationEngine(force: Bool = false) {
        let preparation = currentPreparation()
        let resolvedModelName = preparation.resolvedModelName

        if !force, preparedModelName == resolvedModelName {
            if !isRecording {
                state = .ready
            }
            return
        }

        state = .loading

        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.liveWhisperEngine.prepare(preparation)
                await MainActor.run {
                    guard self.currentPreparation().resolvedModelName == resolvedModelName else { return }
                    self.preparedModelName = resolvedModelName
                    if !self.isRecording {
                        self.state = .ready
                    }
                    if !self.hasRecordedInitialReadyMetric {
                        self.hasRecordedInitialReadyMetric = true
                        self.completeMetric(
                            .launchToReady,
                            context: ["model": resolvedModelName]
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.cancelMetric(.launchToReady)
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func refreshPreparedModelIfNeeded() {
        guard !isRecording else { return }
        let resolvedModelName = currentPreparation().resolvedModelName
        guard preparedModelName != resolvedModelName else { return }
        prewarmDictationEngine()
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
        let menuBarOnlyItem = NSMenuItem(
            title: "Menu Bar Only Mode",
            action: #selector(toggleMenuBarOnlyMode),
            keyEquivalent: ""
        )
        menuBarOnlyItem.target = self
        menuBarOnlyItem.state = menuBarOnlyMode ? .on : .off
        menu.addItem(menuBarOnlyItem)
        self.menuBarOnlyItem = menuBarOnlyItem
        let immersiveItem = NSMenuItem(
            title: "Immersive Mode",
            action: #selector(toggleImmersiveMode),
            keyEquivalent: "i"
        )
        immersiveItem.keyEquivalentModifierMask = [.command, .shift]
        immersiveItem.target = self
        immersiveItem.state = immersiveModeEnabled ? .on : .off
        menu.addItem(immersiveItem)
        self.immersiveModeMenuItem = immersiveItem

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
        registerMenuBarOnlyHotkey()
        refreshCapsLockMonitorIfNeeded()

        hotkeyMonitor = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshHotkeyIfNeeded()
            self?.refreshStatusPositionIfNeeded()
            self?.refreshCapsLockMonitorIfNeeded()
            self?.refreshPreparedModelIfNeeded()
            self?.updateUI()
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

        if menuBarOnlyHotkey == nil {
            registerMenuBarOnlyHotkey()
        }
    }

    private func refreshCapsLockMonitorIfNeeded() {
        if enableCapsLockHoldToDictate {
            installCapsLockEventTapIfNeeded()
        } else {
            removeCapsLockEventTap()
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
        logger.info("Hotkey registered: \(combo.description, privacy: .public)")

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
            logger.warning("Stop hotkey matches start hotkey; skipping stop registration")
            stopHotkey = nil
            return
        }

        currentStopHotkeyKeyCode = stopHotkeyKeyCode
        currentStopHotkeyModifiers = stopHotkeyModifiers
        stopHotkey = HotKey(keyCombo: combo)
        logger.info("Stop hotkey registered: \(combo.description, privacy: .public)")

        stopHotkey?.keyDownHandler = { [weak self] in
            self?.logger.debug("Stop hotkey pressed")
            self?.stopAnyRecording()
        }
    }

    private func registerMenuBarOnlyHotkey() {
        menuBarOnlyHotkey = HotKey(key: .o, modifiers: [.command, .option])
        menuBarOnlyHotkey?.keyDownHandler = { [weak self] in
            self?.toggleMenuBarOnlyMode()
        }
    }

    private func installCapsLockEventTapIfNeeded() {
        guard capsLockEventTap == nil else { return }

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            return appDelegate.handleCapsLockEvent(type: type, event: event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
        else {
            logger.error("Failed to install Caps Lock event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        capsLockEventTap = tap
        capsLockRunLoopSource = source
    }

    private func removeCapsLockEventTap() {
        if let tap = capsLockEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = capsLockRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        capsLockRunLoopSource = nil
        capsLockEventTap = nil
        capsLockDictationPolicy.reset()
    }

    private func handleCapsLockEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard enableCapsLockHoldToDictate else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 57 else {
            return Unmanaged.passUnretained(event)
        }

        let input: CapsLockDictationInput?
        switch type {
        case .keyDown:
            input = .keyDown
        case .keyUp:
            input = .keyUp
        case .flagsChanged:
            input = .flagsChanged(isOn: event.flags.contains(.maskAlphaShift))
        default:
            input = nil
        }

        guard let input else {
            return Unmanaged.passUnretained(event)
        }

        let action = capsLockDictationPolicy.handle(input, isRecording: isRecording)
        switch action {
        case .start:
            DispatchQueue.main.async { [weak self] in
                self?.startRecording(trigger: .capsLock)
            }
        case .stop:
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
        case .none:
            break
        }

        return nil
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
            // Position near the top of the screen (notch area)
            // On Macs with a notch, main.visibleFrame.maxY is usually below the menu bar.
            // Screen.frame.maxY is the absolute top.
            // Let's position it just below the menu bar by default for visibility,
            // but effectively "hugging" it.
            let y = screenFrame.maxY - 10  // Much tighter to the top
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        statusWindow = window

        applyStatusWindowPosition()

        let shouldShowOverlay = showStatusIndicator && !menuBarOnlyMode
        if shouldShowOverlay {
            window.orderFront(nil)
        } else {
            window.orderOut(nil)
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
            // "overlay around dynamic island" preference means tight to top
            y = screenFrame.maxY - 10
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
            startDictation: { [weak self] in self?.startRecording(trigger: .ui) },
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

    private func startRecording(trigger: DictationTrigger = .hotkey) {
        guard case .ready = state else {
            logger.debug("Ignoring start request while not ready")
            return
        }
        guard !isRecording else {
            logger.debug("Ignoring start request while already recording")
            return
        }
        guard !voiceMemoManager.isRecording else {
            logger.debug("Ignoring start request while a voice memo is active")
            return
        }

        captureTargetApp()
        pendingStopTask?.cancel()
        pendingStopTask = nil
        lastVoiceActivityTime = Date().timeIntervalSinceReferenceDate
        lastPartialUpdateTime = lastVoiceActivityTime
        smoothedNoiseFloor = 0
        hasNoiseFloorEstimate = false
        recordingStartTime = lastVoiceActivityTime
        latestSessionPartialTranscript = ""
        maxObservedAudioLevel = 0
        statusViewModel.level = 0
        isRecording = true
        state = .recording
        dictationTask?.cancel()
        hasCompletedHotkeyMetric = false
        hasMarkedSpeechStartMetric = false
        hasCompletedSpeechPartialMetric = false
        markMetric(
            .hotkeyToRecording,
            context: [
                "trigger": trigger.rawValue,
                "model": currentPreparation().resolvedModelName,
            ]
        )
        logger.info(
            "Dictation start trigger=\(trigger.rawValue, privacy: .public) mode=\(self.recordingMode, privacy: .public) autoStop=\(self.autoStopEnabled, privacy: .public) threshold=\(self.autoStopLevelThreshold, privacy: .public)"
        )

        dictationTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor [weak self] in
                    self?.dictationTask = nil
                }
            }

            do {
                let stream = try await self.dictationCoordinator.startDictation()
                for try await update in stream {
                    await self.handleDictationUpdate(update)
                }
            } catch is CancellationError {
                await self.handleCancelledDictation()
            } catch {
                await self.handleDictationFailure(error)
            }
        }

        logger.info("Dictation requested")
    }

    private func stopRecording() {
        guard isRecording || dictationTask != nil else {
            logger.debug("Ignoring stop request while no dictation task is active")
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = recordingStartTime > 0 ? now - recordingStartTime : 0
        if isRecording, elapsed < minimumCaptureDurationForStop {
            let remaining = minimumCaptureDurationForStop - elapsed
            if pendingStopTask == nil {
                logger.debug(
                    "Delaying stop by \(remaining, privacy: .public)s to capture minimum audio window"
                )
                pendingStopTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(
                        nanoseconds: UInt64(max(0, remaining) * 1_000_000_000)
                    )
                    guard let self else { return }
                    self.pendingStopTask = nil
                    self.stopRecordingNow()
                }
            }
            return
        }

        stopRecordingNow()
    }

    private func stopRecordingNow() {
        guard isRecording || dictationTask != nil else {
            return
        }

        pendingStopTask?.cancel()
        pendingStopTask = nil
        isRecording = false
        recordingStartTime = 0
        statusViewModel.level = 0
        state = .processing
        markMetric(.stopToFinal, context: ["model": currentPreparation().resolvedModelName])
        Task { [weak self] in
            await self?.dictationCoordinator.stopDictation()
        }
    }

    private func handleDictationUpdate(_ update: DictationSessionUpdate) async {
        switch update.state {
        case .idle:
            return
        case .preparing:
            await MainActor.run {
                self.isRecording = true
                self.state = .recording
            }
        case .recording:
            if !hasCompletedHotkeyMetric {
                hasCompletedHotkeyMetric = true
                completeMetric(.hotkeyToRecording, context: ["state": update.state.rawValue])
            }
            await MainActor.run {
                self.isRecording = true
                self.state = .recording
            }
        case .partial:
            let trimmedTranscript = update.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTranscript.isEmpty, self.latestSessionPartialTranscript.isEmpty {
                logger.info(
                    "First partial received chars=\(trimmedTranscript.count, privacy: .public)"
                )
            }
            if !trimmedTranscript.isEmpty, !hasMarkedSpeechStartMetric {
                hasMarkedSpeechStartMetric = true
                lastVoiceActivityTime = Date().timeIntervalSinceReferenceDate
            }
            if hasMarkedSpeechStartMetric, !hasCompletedSpeechPartialMetric,
                !trimmedTranscript.isEmpty
            {
                hasCompletedSpeechPartialMetric = true
                completeMetric(
                    .speechStartToFirstPartial,
                    context: ["characters": "\(update.transcript.count)"]
                )
            }
            await MainActor.run {
                if !trimmedTranscript.isEmpty {
                    let now = Date().timeIntervalSinceReferenceDate
                    self.latestSessionPartialTranscript = StreamingTranscriptAccumulator.moreComplete(
                        self.latestSessionPartialTranscript,
                        trimmedTranscript
                    )
                    self.lastPartialUpdateTime = now
                    // A fresh live partial is stronger evidence of ongoing speech
                    // than one low audio-level sample.
                    self.lastVoiceActivityTime = now
                }
                self.lastTranscription = update.transcript
                if self.isRecording {
                    self.state = .recording
                }
            }
        case .finalizing:
            await MainActor.run {
                self.isRecording = false
                self.recordingStartTime = 0
                self.statusViewModel.level = 0
                if !update.transcript.isEmpty {
                    self.latestSessionPartialTranscript = StreamingTranscriptAccumulator.moreComplete(
                        self.latestSessionPartialTranscript,
                        update.transcript
                    )
                    self.lastTranscription = update.transcript
                }
                self.state = .processing
            }
        case .completed:
            logger.info(
                "Completed update chars=\(update.transcript.count, privacy: .public) words=\(update.words.count, privacy: .public)"
            )
            completeMetric(
                .stopToFinal,
                context: ["words": "\(update.words.count)"]
            )
            await finalizeCompletedDictation(update)
        case .failed:
            cancelMetric(.hotkeyToRecording)
            cancelMetric(.speechStartToFirstPartial)
            cancelMetric(.stopToFinal)
            await MainActor.run {
                self.isRecording = false
                self.statusViewModel.level = 0
                self.state = .error(update.errorDescription ?? "Dictation failed")
            }
        }
    }

    private func finalizeCompletedDictation(_ update: DictationSessionUpdate) async {
        await MainActor.run {
            self.isRecording = false
            self.recordingStartTime = 0
            self.pendingStopTask?.cancel()
            self.pendingStopTask = nil
            self.statusViewModel.level = 0
            self.state = .processing
        }

        let rawTranscript = update.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTranscript = StreamingTranscriptAccumulator.moreComplete(
            latestSessionPartialTranscript,
            rawTranscript
        )
        let finalText = CorrectionEngine.shared.apply(to: resolvedTranscript)

        guard !Task.isCancelled else { return }

        guard !finalText.isEmpty else {
            logger.warning(
                "No speech detected rawChars=\(rawTranscript.count, privacy: .public) fallbackChars=\(self.latestSessionPartialTranscript.count, privacy: .public) maxLevel=\(self.maxObservedAudioLevel, privacy: .public)"
            )
            await MainActor.run {
                self.latestSessionPartialTranscript = ""
                self.lastTranscription = "(no speech detected)"
                self.state = .ready
            }
            return
        }

        await MainActor.run {
            self.activateTargetApp()
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else { return }

        let duration = Float(update.words.last?.end ?? 0)

        do {
            let insertionRequest = await MainActor.run { () -> TextInsertionRequest in
                if self.alwaysCopyToClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalText, forType: .string)
                }

                return TextInsertionRequest(
                    text: finalText,
                    targetApp: self.currentInsertionTargetProfile(),
                    preserveClipboard: !self.alwaysCopyToClipboard
                )
            }

            let result = try await self.textInsertionService.insert(insertionRequest)

            await MainActor.run {
                self.latestSessionPartialTranscript = ""
                self.addHistoryEntry(
                    text: finalText,
                    duration: duration,
                    method: self.outputMethod(for: result.strategy)
                )
                self.lastTranscription = finalText
                self.state = .ready
                self.updateHistoryMenu()
                self.logger.info(
                    "Text inserted using \(result.strategy.rawValue, privacy: .public)"
                )
            }
        } catch {
            await MainActor.run {
                self.latestSessionPartialTranscript = ""
                self.logger.error("Text insertion failed: \(error.localizedDescription, privacy: .public)")
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
                self.lastTranscription = "Copied: \(finalText)"
                self.addHistoryEntry(text: finalText, duration: duration, method: .clipboard)
                self.state = .ready
                self.updateHistoryMenu()
            }
        }
    }

    private func handleDictationFailure(_ error: Error) async {
        guard !Task.isCancelled else { return }

        await MainActor.run {
            self.isRecording = false
            self.recordingStartTime = 0
            self.latestSessionPartialTranscript = ""
            self.pendingStopTask?.cancel()
            self.pendingStopTask = nil
            self.statusViewModel.level = 0
            self.state = .error(error.localizedDescription)
        }
    }

    private func handleCancelledDictation() async {
        cancelMetric(.hotkeyToRecording)
        cancelMetric(.speechStartToFirstPartial)
        cancelMetric(.stopToFinal)
        await MainActor.run {
            self.isRecording = false
            self.recordingStartTime = 0
            self.latestSessionPartialTranscript = ""
            self.pendingStopTask?.cancel()
            self.pendingStopTask = nil
            self.statusViewModel.level = 0
            if case .processing = self.state {
                return
            }
            self.state = .ready
        }
    }

    private func currentInsertionTargetProfile() -> InsertionAppProfile {
        InsertionAppProfileCatalog.resolve(
            bundleIdentifier: lastTargetBundleIdentifier ?? lastTargetApp?.bundleIdentifier,
            applicationName: lastTargetApp?.localizedName ?? "",
            userPrefersPaste: usePaste
        )
    }

    private func outputMethod(for strategy: TextInsertionStrategy) -> OutputMethod {
        switch strategy {
        case .axInsert:
            return .ax
        case .paste:
            return .paste
        case .type:
            return .type
        }
    }

    private func abortTranscription() {
        guard case .processing = state else { return }
        logger.info("Aborting transcription")
        dictationTask?.cancel()
        dictationTask = nil
        recordingStartTime = 0
        latestSessionPartialTranscript = ""
        pendingStopTask?.cancel()
        pendingStopTask = nil
        Task { [weak self] in
            await self?.dictationCoordinator.stopDictation()
        }
        cancelMetric(.stopToFinal)
        state = .ready
        statusViewModel.level = 0
    }

    private func handleAudioLevel(_ level: Float) {
        let mode = RecordingModePreference(rawValue: recordingMode) ?? .hold
        guard isRecording,
            DictationStopPolicy.allowsAutomaticStop(
                recordingMode: mode,
                isEnabled: autoStopEnabled
            )
        else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if level > maxObservedAudioLevel {
            maxObservedAudioLevel = level
        }

        if !hasNoiseFloorEstimate {
            smoothedNoiseFloor = level
            hasNoiseFloorEstimate = true
        } else if level <= smoothedNoiseFloor {
            smoothedNoiseFloor = (smoothedNoiseFloor * 0.85) + (level * 0.15)
        } else {
            // Raise floor slowly so short spikes do not disable silence detection.
            smoothedNoiseFloor = (smoothedNoiseFloor * 0.98) + (level * 0.02)
        }

        let dynamicSpeechThreshold = max(
            autoStopLevelThreshold,
            smoothedNoiseFloor + autoStopRelativeSpeechDelta
        )

        if level >= dynamicSpeechThreshold {
            lastVoiceActivityTime = now
            if !hasMarkedSpeechStartMetric {
                hasMarkedSpeechStartMetric = true
                markMetric(.speechStartToFirstPartial)
            }
            return
        }

        if !hasMarkedSpeechStartMetric {
            if recordingStartTime > 0, now - recordingStartTime >= autoStopNoSpeechTimeout {
                logger.debug("Auto-stop triggered after no-speech timeout")
                stopRecording()
            }
            return
        }

        let silenceWindow = max(0.7, autoStopSilenceSeconds)
        if DictationStopPolicy.shouldStopAfterSilence(
            now: now,
            lastVoiceActivity: lastVoiceActivityTime,
            lastPartialUpdate: lastPartialUpdateTime,
            hasPartialTranscript: !latestSessionPartialTranscript.isEmpty,
            silenceWindow: silenceWindow,
            trailingPartialGrace: autoStopTrailingPartialGrace
        ) {
            logger.debug("Auto-stop triggered after silence")
            stopRecording()
        }
    }

    private func handleStartHotkeyDown() {
        if recordingMode == "toggle" {
            if isRecording {
                logger.debug("Start hotkey toggled stop")
                stopRecording()
            } else {
                logger.debug("Start hotkey toggled start")
                startRecording(trigger: .hotkey)
            }
        } else {
            logger.debug("Start hotkey pressed")
            startRecording(trigger: .hotkey)
        }
    }

    private func handleStartHotkeyUp() {
        if recordingMode == "hold" {
            logger.debug("Start hotkey released")
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

    private func addHistoryEntry(text: String, duration: Float, method: OutputMethod) {
        dictationHistory.addEntry(
            text: text,
            durationSeconds: Double(duration),
            model: selectedModel,
            outputMethod: method.value(withClipboard: alwaysCopyToClipboard)
        )
    }

    private func markMetric(_ metric: WhisperMetric, context: [String: String] = [:]) {
        Task {
            await WhisperTelemetry.shared.mark(metric, context: context)
        }
    }

    private func completeMetric(_ metric: WhisperMetric, context: [String: String] = [:]) {
        Task {
            await WhisperTelemetry.shared.complete(metric, additionalContext: context)
        }
    }

    private func cancelMetric(_ metric: WhisperMetric) {
        Task {
            await WhisperTelemetry.shared.cancel(metric)
        }
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

        // Update status window — immersive mode supplies its own recording surface.
        if let window = statusWindow {
            let shouldShowOverlay = showStatusIndicator && !menuBarOnlyMode && !immersiveModeEnabled
            if shouldShowOverlay {
                window.orderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }

        menuBarOnlyItem?.state = menuBarOnlyMode ? .on : .off

        // Immersive mode stays visually continuous from recording through transcription.
        if immersiveModeEnabled {
            if state.isRecording || state == .processing {
                showImmersiveWindow()
                processingBarWindow?.orderOut(nil)
            } else {
                immersiveModeWindow?.orderOut(nil)
                processingBarWindow?.orderOut(nil)
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

    @objc private func toggleMenuBarOnlyMode() {
        menuBarOnlyMode.toggle()
        updateUI()
    }

    @objc private func toggleImmersiveMode() {
        immersiveModeEnabled.toggle()
        immersiveModeMenuItem?.state = immersiveModeEnabled ? .on : .off
        // Actual show/hide is driven by updateUI via state changes
        if !immersiveModeEnabled {
            immersiveModeWindow?.orderOut(nil)
        }
        updateUI()
    }

    private func showImmersiveWindow() {
        if immersiveModeWindow == nil {
            setupImmersiveWindow()
        }
        immersiveModeWindow?.orderFrontRegardless()
    }

    private func setupImmersiveWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let dockInset = max(0, screen.visibleFrame.minY - screenFrame.minY)
        let hostingView = NSHostingView(
            rootView: ImmersiveWaveformView(
                viewModel: statusViewModel,
                bottomInset: dockInset
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: screenFrame.size)
        hostingView.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        self.immersiveModeWindow = window
    }

    private func showProcessingBar() {
        if processingBarWindow == nil { setupProcessingBarWindow() }
        processingBarWindow?.orderFrontRegardless()
    }

    private func setupProcessingBarWindow() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        let barHeight = CGFloat(6)
        let windowFrame = NSRect(x: sf.minX, y: sf.minY, width: sf.width, height: barHeight)

        let hostingView = NSHostingView(rootView: ImmersiveProcessingView())
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        self.processingBarWindow = window
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

    func applicationWillTerminate(_ notification: Notification) {
        removeCapsLockEventTap()
    }
}

private final class FixedSizeHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 70)
    }
}
