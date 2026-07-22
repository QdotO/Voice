import Foundation

public enum DictationRecordingTrigger: String, Equatable, Sendable {
    case hotkey
    case capsLock
    case ui
}

public enum DictationStopInstructionPolicy {
    public static func instruction(
        trigger: DictationRecordingTrigger,
        capsLockEnabled: Bool,
        stopHotkeyDisplay: String?
    ) -> String {
        if trigger == .capsLock, capsLockEnabled {
            return "Release Caps Lock to stop"
        }

        guard let stopHotkeyDisplay,
            !stopHotkeyDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            stopHotkeyDisplay.caseInsensitiveCompare("Unassigned") != .orderedSame
        else {
            return "Use menu bar to stop"
        }

        return "Press \(stopHotkeyDisplay) to stop"
    }
}

public enum DictationFailureKind: String, Equatable, Sendable {
    case accessibility
    case microphone
    case model
    case unknown
}

public enum DictationRecoveryAction: Equatable, Sendable {
    case retry
    case openPermissions
    case openSettings
}

public enum DictationSemanticRole: String, Equatable, Sendable {
    case processing
    case ready
    case active
    case danger
}

public enum DictationPresentationState: Equatable, Sendable {
    case preparingModel
    case ready
    case listening
    case transcribing
    case failure(kind: DictationFailureKind, detail: String)
}

public struct DictationStatePresentation: Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let role: DictationSemanticRole
    public let statusItemAccessibilityDescription: String
    public let recoveryAction: DictationRecoveryAction?

    public init(state: DictationPresentationState) {
        var accessibilityDetail: String?
        switch state {
        case .preparingModel:
            title = "Preparing model"
            detail = nil
            role = .processing
            recoveryAction = nil
        case .ready:
            title = "Ready"
            detail = nil
            role = .ready
            recoveryAction = nil
        case .listening:
            title = "Listening"
            detail = nil
            role = .active
            recoveryAction = nil
        case .transcribing:
            title = "Transcribing"
            detail = nil
            role = .processing
            recoveryAction = nil
        case let .failure(kind, rawDetail):
            title = Self.title(for: kind)
            detail = Self.boundedDetail(rawDetail)
            accessibilityDetail = rawDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            role = .danger
            recoveryAction = Self.recoveryAction(for: kind)
        }

        var accessibility = "Whisper status: \(title)"
        if let accessibilityDetail, !accessibilityDetail.isEmpty {
            accessibility += ". \(accessibilityDetail)"
        }
        statusItemAccessibilityDescription = accessibility
    }

    public static func classifyFailure(_ detail: String) -> DictationFailureKind {
        let value = detail.lowercased()

        if value.contains("accessibility") || value.contains("axisprocesstrusted") {
            return .accessibility
        }
        if value.contains("microphone") || value.contains("audio input")
            || value.contains("recording permission")
        {
            return .microphone
        }
        if value.contains("model") || value.contains("whisper") || value.contains("tokenizer")
            || value.contains("engine")
        {
            return .model
        }
        return .unknown
    }

    public static func boundedDetail(_ value: String, maxLines: Int = 2, maxCharactersPerLine: Int = 120) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, maxLines > 0, maxCharactersPerLine > 0 else { return "" }

        let sourceLines = normalized.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        var lines = sourceLines.prefix(maxLines).map {
            let line = String($0)
            guard line.count > maxCharactersPerLine else { return line }
            return String(line.prefix(max(0, maxCharactersPerLine - 1))) + "…"
        }

        if sourceLines.count > maxLines {
            if lines.isEmpty {
                lines = ["…"]
            } else {
                let lastIndex = lines.index(before: lines.endIndex)
                let line = lines[lastIndex]
                lines[lastIndex] = String(line.prefix(max(0, maxCharactersPerLine - 1))) + "…"
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func title(for kind: DictationFailureKind) -> String {
        switch kind {
        case .accessibility:
            return "Accessibility access needed"
        case .microphone:
            return "Microphone access needed"
        case .model:
            return "Model could not load"
        case .unknown:
            return "Dictation failed"
        }
    }

    private static func recoveryAction(for kind: DictationFailureKind) -> DictationRecoveryAction {
        switch kind {
        case .accessibility, .microphone:
            return .openPermissions
        case .model:
            return .retry
        case .unknown:
            return .openSettings
        }
    }
}

public struct FloatingWaveColorSelection: Equatable, Sendable {
    public let primaryHex: String
    public let secondaryHex: String
    public let usesFallback: Bool

    public init(primaryHex: String, secondaryHex: String, usesFallback: Bool) {
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.usesFallback = usesFallback
    }
}

public enum FloatingWaveColorResolver {
    public static let fallback = FloatingWaveColorSelection(
        primaryHex: "#FF6A32",
        secondaryHex: "#FF9A62",
        usesFallback: true
    )

    public static func resolve(useCustomColor: Bool, hex: String) -> FloatingWaveColorSelection {
        guard useCustomColor, let rgb = RGB(hex: hex) else { return fallback }

        let primary = rgb.hex
        let secondary = rgb.lightened(by: 0.22).hex
        return FloatingWaveColorSelection(
            primaryHex: primary,
            secondaryHex: secondary,
            usesFallback: false
        )
    }

    private struct RGB {
        let red: Int
        let green: Int
        let blue: Int

        init?(hex: String) {
            let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
            guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
            red = Int((number >> 16) & 0xFF)
            green = Int((number >> 8) & 0xFF)
            blue = Int(number & 0xFF)
        }

        var hex: String {
            String(format: "#%02X%02X%02X", red, green, blue)
        }

        func lightened(by amount: Double) -> RGB {
            RGB(
                red: min(255, Int(round(Double(red) + Double(255 - red) * amount))),
                green: min(255, Int(round(Double(green) + Double(255 - green) * amount))),
                blue: min(255, Int(round(Double(blue) + Double(255 - blue) * amount)))
            )
        }

        private init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }
}

public enum FloatingStatusLayout {
    public static let islandWidth: Double = 300
}
