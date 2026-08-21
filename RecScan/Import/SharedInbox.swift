import Foundation

/// The handover point between the share extension and the app.
///
/// Responsibilities:
/// - Resolve the App Group container and list what has been dropped there.
/// - Clear items once the app has taken them.
///
/// ## Why a folder and not a database
/// An extension runs in its own process and cannot open the app's SwiftData store. The
/// App Group container is the only storage both can see, so the extension writes files and
/// the app imports them through its ordinary pipeline — which keeps the date and
/// rasterisation rules in exactly one place rather than duplicated into an extension.
enum SharedInbox {

    /// Must match the identifier in `ShareExtension/ShareViewController.swift` and in both
    /// entitlements files. Changing it means changing all four.
    static let appGroupIdentifier = "group.io.shkalash.recscan"
    private static let folderName = "ShareInbox"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: folderName)
    }

    /// Files waiting to be imported, oldest first so a batch keeps the order it arrived in.
    static func pendingURLs() -> [URL] {
        guard let containerURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        return contents.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left < right
        }
    }

    /// Removes files the app has finished with.
    ///
    /// Called only after a successful import: leaving them on failure means the next
    /// launch tries again rather than silently dropping what was shared.
    static func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}
