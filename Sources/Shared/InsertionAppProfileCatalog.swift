import Foundation

public enum InsertionAppProfileCatalog {
    public static let version = "1"

    private static let axEditorBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeInsiders2",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",
    ]

    private static let axEditorNamePatterns: [String] = [
        "Visual Studio Code",
        "VS Code",
        "Cursor",
    ]

    private static let editorBundleIdentifiers: Set<String> = [
        "com.apple.TextEdit",
        "com.apple.dt.Xcode",
        "com.barebones.bbedit",
        "com.panic.Nova",
        "dev.zed.Zed",
        "com.sublimetext.4",
    ]

    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser",
    ]

    private static let chatBundleIdentifiers: Set<String> = [
        "com.apple.MobileSMS",
        "com.hnc.Discord",
        "com.microsoft.teams2",
        "com.tdesktop.Telegram",
        "com.tinyspeck.slackmacgap",
    ]

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "org.alacritty",
    ]

    public static func resolve(
        bundleIdentifier: String?,
        applicationName: String,
        userPrefersPaste: Bool = false
    ) -> InsertionAppProfile {
        let normalizedName = normalizedApplicationName(applicationName, bundleIdentifier: bundleIdentifier)
        let bundleIdentifier = normalize(bundleIdentifier)

        let baseProfile: InsertionAppProfile
        if matchesAXEditor(bundleIdentifier: bundleIdentifier, applicationName: normalizedName) {
            baseProfile = InsertionAppProfile(
                bundleIdentifier: bundleIdentifier,
                applicationName: normalizedName,
                version: version,
                preferredStrategy: .axInsert,
                fallbackStrategies: [.paste, .type]
            )
        } else if matches(bundleIdentifier, in: editorBundleIdentifiers) {
            baseProfile = makeProfile(
                bundleIdentifier: bundleIdentifier,
                applicationName: normalizedName,
                preferredStrategy: .paste,
                fallbackStrategies: [.type]
            )
        } else if matches(bundleIdentifier, in: browserBundleIdentifiers)
            || matches(bundleIdentifier, in: chatBundleIdentifiers)
        {
            baseProfile = makeProfile(
                bundleIdentifier: bundleIdentifier,
                applicationName: normalizedName,
                preferredStrategy: .paste,
                fallbackStrategies: [.type]
            )
        } else if matches(bundleIdentifier, in: terminalBundleIdentifiers) {
            baseProfile = makeProfile(
                bundleIdentifier: bundleIdentifier,
                applicationName: normalizedName,
                preferredStrategy: .type,
                fallbackStrategies: [.paste]
            )
        } else {
            baseProfile = makeProfile(
                bundleIdentifier: bundleIdentifier,
                applicationName: normalizedName,
                preferredStrategy: .type,
                fallbackStrategies: [.paste]
            )
        }

        guard userPrefersPaste, baseProfile.preferredStrategy != .axInsert else {
            return baseProfile
        }

        return makeProfile(
            bundleIdentifier: baseProfile.bundleIdentifier,
            applicationName: baseProfile.applicationName,
            preferredStrategy: .paste,
            fallbackStrategies: uniqueStrategies([baseProfile.preferredStrategy] + baseProfile.fallbackStrategies)
        )
    }

    private static func matchesAXEditor(bundleIdentifier: String?, applicationName: String) -> Bool {
        if matches(bundleIdentifier, in: axEditorBundleIdentifiers) {
            return true
        }

        let foldedName = applicationName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return axEditorNamePatterns.contains {
            foldedName.localizedCaseInsensitiveContains($0)
        }
    }

    private static func makeProfile(
        bundleIdentifier: String?,
        applicationName: String,
        preferredStrategy: TextInsertionStrategy,
        fallbackStrategies: [TextInsertionStrategy]
    ) -> InsertionAppProfile {
        InsertionAppProfile(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            version: version,
            preferredStrategy: preferredStrategy,
            fallbackStrategies: uniqueStrategies(fallbackStrategies)
        )
    }

    private static func uniqueStrategies(_ strategies: [TextInsertionStrategy]) -> [TextInsertionStrategy] {
        var seen: Set<TextInsertionStrategy> = []
        return strategies.filter { seen.insert($0).inserted }
    }

    private static func normalizedApplicationName(
        _ value: String,
        bundleIdentifier: String?
    ) -> String {
        let normalizedValue = normalize(value)
        if let normalizedValue {
            return normalizedValue
        }
        if let bundleIdentifier {
            return bundleIdentifier
        }
        return "Unknown App"
    }

    private static func matches(_ candidate: String?, in values: Set<String>) -> Bool {
        guard let candidate else { return false }
        return values.contains(candidate)
    }

    private static func normalize(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}
