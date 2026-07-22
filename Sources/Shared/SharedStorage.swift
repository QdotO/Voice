import Foundation

public enum SharedStorage {
    private static let appGroupIDSnapshot = LockedSnapshot<String?>(nil)

    public static var appGroupID: String? {
        get {
            appGroupIDSnapshot.read()
        }
        set {
            appGroupIDSnapshot.replace(with: newValue)
        }
    }

    public static func baseDirectory() -> URL {
        let appGroupID = appGroupID

        if let appGroupID,
           let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
           ) {
            return containerURL
        }

        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    }
}
