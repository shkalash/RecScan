import Foundation

/// Runs recognition jobs strictly one at a time.
///
/// Responsibilities:
/// - Serialise background work so a bulk import cannot start fifty at once.
///
/// ## Why an actor alone is not enough
/// An actor serialises entry, but recognition suspends on `await`, and actors are reentrant
/// — a second job would start during the first one's suspension. Chaining each job onto the
/// previous one's completion is what actually guarantees one at a time.
///
/// The caution is earned: the Simulator's HEVC encoder deadlocked outright at around a dozen
/// concurrent calls earlier in this project. Vision has not been measured, so it gets the
/// same treatment until it has been.
actor TextRecognitionQueue {

    private var tail: Task<Void, Never>?

    /// Appends `work`, to run after everything already queued.
    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await work()
        }
    }

    /// Waits for everything queued so far. Used by tests; nothing in the app blocks on it.
    func drain() async {
        await tail?.value
    }
}
