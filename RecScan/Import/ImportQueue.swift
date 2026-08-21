import Foundation

/// Gathers files that arrive one at a time into a single batch.
///
/// Responsibilities:
/// - Hold incoming URLs briefly and hand them over together.
///
/// ## Why this exists
/// `.onOpenURL` is called **once per URL**. Sharing five files delivers five separate
/// callbacks in quick succession, and importing on each one would raise five review
/// sheets — each replacing the last, so four batches would be silently left unreviewed.
///
/// A short debounce turns that back into the one batch the user actually shared. The
/// window is deliberately small: long enough to catch a burst from a single share, short
/// enough that a genuine single file still feels immediate.
@MainActor
final class ImportQueue {

    private var pending: [URL] = []
    private var flushTask: Task<Void, Never>?
    private let window: Duration

    init(window: Duration = .milliseconds(AppConstants.Interaction.importCoalesceMilliseconds)) {
        self.window = window
    }

    /// Adds a URL and restarts the window.
    ///
    /// Each arrival pushes the flush back, so a burst is delivered once it stops rather
    /// than being cut in half by a fixed timer.
    func enqueue(_ url: URL, flush: @escaping @MainActor ([URL]) async -> Void) {
        pending.append(url)
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.window ?? .milliseconds(0))
            guard !Task.isCancelled, let self else { return }
            let batch = self.pending
            self.pending = []
            guard !batch.isEmpty else { return }
            await flush(batch)
        }
    }

    /// Hands over whatever is waiting immediately.
    func flushNow(_ flush: @escaping @MainActor ([URL]) async -> Void) async {
        flushTask?.cancel()
        let batch = pending
        pending = []
        guard !batch.isEmpty else { return }
        await flush(batch)
    }

    var isEmpty: Bool { pending.isEmpty }
}
