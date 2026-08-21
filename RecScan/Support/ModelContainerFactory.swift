import Foundation
import SwiftData

/// Creates the app's SwiftData container.
///
/// Responsibilities:
/// - Own the schema definition and the on-disk/in-memory configuration choice.
///
/// Why it is separate from the `App`: previews, tests and the live app all need a
/// container, and only the live app should get the persistent one.
enum ModelContainerFactory {

    /// Every `@Model` type the app persists.
    static let schema = Schema([Receipt.self, ReceiptCategory.self])

    /// Persistent container backing the running app.
    static func makeContainer() throws -> ModelContainer {
        try createApplicationSupportDirectoryIfNeeded()
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        )
    }

    /// Throwaway container for previews and tests.
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// Shared in-memory container used as the environment default.
    ///
    /// Deliberately not actor-isolated: `EnvironmentValues` defaults are evaluated in a
    /// nonisolated context. `ModelContainer` is `Sendable`, so a plain global `let` is
    /// safe and is initialised lazily on first use.
    ///
    /// Trapping is deliberate: a schema that cannot even be loaded in memory is a
    /// programming error that must fail loudly, not degrade silently.
    /// Creates `Library/Application Support` when it does not yet exist.
    ///
    /// SwiftData puts `default.store` there but does not create the directory first.
    /// On a fresh install it therefore fails, emits roughly two hundred lines of
    /// filesystem diagnostics to the console, and only then recovers by creating the
    /// directory itself. The store ends up fine either way — this exists purely so a
    /// first launch does not look like a catastrophe in the log.
    private static func createApplicationSupportDirectoryIfNeeded() throws {
        let fileManager = FileManager.default
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard !fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static let preview: ModelContainer = {
        do {
            return try makeInMemoryContainer()
        } catch {
            fatalError("Failed to build the in-memory preview container: \(error)")
        }
    }()
}
