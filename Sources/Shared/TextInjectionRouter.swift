import Foundation

/// Determines which text injection strategy to use for a given target application.
/// Extracted from AppDelegate to enable unit testing of the routing logic.
public struct TextInjectionRouter {

    public enum Strategy: Equatable, Sendable {
        case axInsert    // Accessibility API insertion (preferred for editors like VS Code)
        case paste       // Cmd+V paste
        case type        // Character-by-character CGEvent posting
    }

    /// Bundle IDs that require AX insertion for proper text injection.
    public static let axInsertBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeInsiders2",
        "com.vscodium",
    ]

    /// Bundle IDs that require paste for proper text injection.
    public static let pasteBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeInsiders2",
        "com.vscodium",
    ]

    /// Name substrings that indicate an AX-insert target.
    public static let axInsertNamePatterns: [String] = [
        "Visual Studio Code - Insiders",
        "VS Code Insiders",
    ]

    /// Name substrings that indicate a paste target.
    public static let pasteNamePatterns: [String] = [
        "Visual Studio Code - Insiders",
        "VS Code Insiders",
    ]

    /// Determine the injection strategy for a given target app.
    ///
    /// - Parameters:
    ///   - bundleID: The target app's bundle identifier (may be nil).
    ///   - appName: The target app's display name.
    ///   - userPrefersPaste: Whether the user has toggled the global "use paste" preference.
    /// - Returns: The strategy to use for text injection.
    public static func strategy(
        bundleID: String?,
        appName: String,
        userPrefersPaste: Bool
    ) -> Strategy {
        // AX insert takes highest priority (specific editor support)
        if shouldForceAXInsert(bundleID: bundleID, appName: appName) {
            return .axInsert
        }

        // User preference or app-specific paste requirement
        if userPrefersPaste || shouldForcePaste(bundleID: bundleID, appName: appName) {
            return .paste
        }

        // Default: character-by-character typing
        return .type
    }

    public static func shouldForceAXInsert(bundleID: String?, appName: String) -> Bool {
        if let bundleID, axInsertBundleIDs.contains(bundleID) {
            return true
        }
        for pattern in axInsertNamePatterns {
            if appName.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }
        return false
    }

    public static func shouldForcePaste(bundleID: String?, appName: String) -> Bool {
        if let bundleID, pasteBundleIDs.contains(bundleID) {
            return true
        }
        for pattern in pasteNamePatterns {
            if appName.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }
        return false
    }
}
