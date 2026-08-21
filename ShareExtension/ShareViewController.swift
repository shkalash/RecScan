import UIKit
import UniformTypeIdentifiers

/// Receives images and PDFs shared from other apps.
///
/// Responsibilities:
/// - Copy whatever was shared into the shared container.
/// - Finish immediately, without asking anything.
///
/// ## Why it writes files instead of importing
/// An extension runs in its own process with its own storage and cannot open the app's
/// SwiftData store. The App Group container is the only place both can see, so the
/// extension's whole job is to drop the payload somewhere the app will find it. The app
/// drains that folder when it next comes to the foreground and runs its ordinary import,
/// which keeps every date and rasterisation rule in one place.
///
/// There is deliberately no UI: the receipts land flagged for review, so the details can
/// be filled in inside the app where the full form already lives.
final class ShareViewController: UIViewController {

    /// Must match `SharedContainer.appGroupIdentifier` in the app.
    ///
    /// Duplicated rather than shared: hoisting ten lines into a framework, or into both
    /// targets' membership, costs more than it saves — but the two must be changed together.
    private static let appGroupIdentifier = "group.io.shkalash.recscan"
    private static let inboxFolderName = "ShareInbox"

    override func viewDidLoad() {
        super.viewDidLoad()
        receiveSharedItems()
    }

    /// Copies every shared attachment into the shared inbox, then finishes.
    ///
    /// Completion handlers rather than `async`: `NSItemProvider` is not `Sendable`, so
    /// carrying one across an await is a data race under Swift 6's checking. Staying
    /// callback-based keeps the provider on one thread and needs no unsafe opt-out.
    private func receiveSharedItems() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        let group = DispatchGroup()

        for provider in providers {
            // PDF first: a PDF also conforms to no image type, but checking in this order
            // keeps the intent obvious if that ever changes.
            for type in [UTType.pdf, UTType.image]
            where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    if let data {
                        Self.write(data, pathExtension: type == .pdf ? "pdf" : "img")
                    }
                    group.leave()
                }
                break
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Writes one payload into the shared inbox.
    ///
    /// `static` because it runs on whichever queue the item provider calls back on, and
    /// touching the view controller from there would be a race.
    /// Named with a UUID so two shares in quick succession cannot collide.
    private static func write(_ data: Data, pathExtension: String) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }

        let inbox = container.appending(path: inboxFolderName)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try? data.write(to: inbox.appending(path: "\(UUID().uuidString).\(pathExtension)"), options: .atomic)
    }
}

