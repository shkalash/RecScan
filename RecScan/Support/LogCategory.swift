import Foundation
import OSLog

/// Logging categories used across the app.
///
/// Responsibilities:
/// - Own the (non user facing) category strings so no call site spells one inline.
/// - Vend a configured `Logger` per subsystem area.
enum LogCategory: String {
    case storage
    case capture
    case export
    case persistence

    var logger: Logger {
        Logger(subsystem: AppConstants.Identifier.logSubsystem, category: rawValue)
    }
}
