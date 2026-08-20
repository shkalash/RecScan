import SwiftUI
import UIKit
import VisionKit

/// Bridges `VNDocumentCameraViewController` into SwiftUI.
///
/// Responsibilities:
/// - Present the system document camera.
/// - Hand the captured pages back, in order, to the caller.
///
/// ## Why the system scanner rather than `AVCaptureSession`
/// It supplies edge detection, perspective correction, shadow removal and multi-page
/// capture in one already-shipped session. A hand-rolled camera would take weeks to
/// approximate any one of those.
///
/// The pages it returns are already deskewed and cropped. Do not run further
/// `CIFilter` correction over them — it degrades an already-corrected image.
struct DocumentScanner: UIViewControllerRepresentable {

    /// Called with the captured pages in page order. Empty results are never delivered.
    let onScan: ([UIImage]) -> Void

    /// Called when the user cancels or the camera fails.
    let onFinish: (Error?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {
        // The controller is fully configured at creation; SwiftUI state does not drive it.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFinish: onFinish)
    }

    /// Retains the delegate callbacks for the lifetime of the presented controller.
    ///
    /// Responsibilities:
    /// - Translate `VNDocumentCameraScan` into an ordered array of images.
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {

        private let onScan: ([UIImage]) -> Void
        private let onFinish: (Error?) -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onFinish: @escaping (Error?) -> Void) {
            self.onScan = onScan
            self.onFinish = onFinish
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            onFinish(error)
        }
    }
}
