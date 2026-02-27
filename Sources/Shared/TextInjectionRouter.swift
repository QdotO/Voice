import Foundation

/// Determines which text injection strategy to use for a given target application.
/// Extracted from AppDelegate to enable unit testing of the routing logic.
public struct TextInjectionRouter {

    public enum Strategy: Equatable, Sendable {
        case axInsert  // Accessibility API insertion (preferred for editors like VS Code)
        case paste  // Cmd+V paste
        case type  // Character-by-character CGEvent posting
    }

    /// Bundle IDs used for editor-specific routing (VS Code family).
    public static let vscodeEditorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeInsiders2",
        "com.vscodium",
    ]

    /// Backward-compatible alias for tests and existing callers.
    public static let axInsertBundleIDs: Set<String> = vscodeEditorBundleIDs
    /// Backward-compatible alias for tests and existing callers.
    public static let pasteBundleIDs: Set<String> = vscodeEditorBundleIDs

    /// Name patterns used for editor-specific routing (VS Code family).
    public static let vscodeEditorNamePatterns: [String] = [
        "Visual Studio Code - Insiders",
        "VS Code Insiders",
    ]

    /// Backward-compatible alias for tests and existing callers.
    public static let axInsertNamePatterns: [String] = vscodeEditorNamePatterns
    /// Backward-compatible alias for tests and existing callers.
    public static let pasteNamePatterns: [String] = vscodeEditorNamePatterns

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
        matchesVSCodeEditor(bundleID: bundleID, appName: appName)
    }

    public static func shouldForcePaste(bundleID: String?, appName: String) -> Bool {
        matchesVSCodeEditor(bundleID: bundleID, appName: appName)
    }

    private static func matchesVSCodeEditor(bundleID: String?, appName: String) -> Bool {
        if let bundleID, vscodeEditorBundleIDs.contains(bundleID) {
            return true
        }
        for pattern in vscodeEditorNamePatterns {
            if appName.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }
        return false
    }
}
