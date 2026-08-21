import Foundation

/// Application-wide constants that are not user facing.
///
/// Responsibilities:
/// - Provide a single, typed home for identifiers and tuning values that are shared
///   across more than one module boundary.
///
/// Why a caseless `enum`: it cannot be instantiated, so it reads purely as a namespace.
/// Values scoped to a single subsystem live next to that subsystem instead of here
/// (see `StorageConstants`, `PDFMetrics`, `LayoutMetrics`).
enum AppConstants {

    /// Identifiers used for logging subsystems and file naming.
    enum Identifier {
        /// Read from the bundle rather than hardcoded, so renaming the app in Xcode
        /// cannot silently leave log output filed under a stale subsystem.
        static let logSubsystem = Bundle.main.bundleIdentifier ?? fallbackSubsystem

        /// Used only when there is no bundle identifier to read, which in practice
        /// means a unit-test host that has not been configured with one.
        private static let fallbackSubsystem = "RecScan"
    }

    /// Timings for interactions that must wait on a presentation animation.
    enum Interaction {
        /// Delay before requesting focus inside a freshly presented popover or sheet.
        /// Short enough to feel immediate, long enough that the field is in the window.
        static let focusDelayMilliseconds = 350

        /// Window for gathering files that arrive one callback at a time. Long enough to
        /// catch a burst from one share, short enough that a single file still feels
        /// immediate.
        static let importCoalesceMilliseconds = 400
    }

    /// Formatting values shared by the library, detail and export layers.
    enum Format {
        /// Timestamp fragment used when naming generated export files.
        /// Chosen to sort lexicographically and to contain no characters that are
        /// illegal in a file name on any platform the file might be shared to.
        static let exportFileTimestamp = "yyyy-MM-dd-HHmmss"
        static let posixLocaleIdentifier = "en_US_POSIX"
    }
}
