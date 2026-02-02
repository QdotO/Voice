import Foundation

public enum SharedStorage {
    public static var appGroupID: String?

    public static func baseDirectory() -> URL {
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
