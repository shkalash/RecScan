import SwiftUI
import UIKit

/// A pinch-and-pan zoomable image.
///
/// Responsibilities:
/// - Present a single image with the platform's own zoom behaviour.
///
/// ## Why `UIScrollView` and not SwiftUI gestures
/// `MagnifyGesture` composed with `DragGesture` reproduces neither rubber-banding,
/// zoom-to-point, nor double-tap-to-zoom, and it fights the enclosing scroll view.
/// `UIScrollView` supplies all of it and is the same code path the Photos app uses.
struct ZoomableImageView: UIViewRepresentable {

    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = LayoutMetrics.Detail.minimumZoomScale
        scrollView.maximumZoomScale = LayoutMetrics.Detail.maximumZoomScale
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard context.coordinator.imageView?.image !== image else { return }
        context.coordinator.imageView?.image = image
        scrollView.setZoomScale(LayoutMetrics.Detail.minimumZoomScale, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the scroll view's zoom delegate callbacks.
    final class Coordinator: NSObject, UIScrollViewDelegate {

        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc
        func handleDoubleTap(_ recogniser: UITapGestureRecognizer) {
            guard let scrollView = imageView?.superview as? UIScrollView else { return }

            if scrollView.zoomScale > LayoutMetrics.Detail.minimumZoomScale {
                scrollView.setZoomScale(LayoutMetrics.Detail.minimumZoomScale, animated: true)
                return
            }

            // Zoom in around the tapped point rather than the centre, so a double tap
            // on a total line brings that line up.
            let point = recogniser.location(in: imageView)
            let scale = LayoutMetrics.Detail.doubleTapZoomScale
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
}

#if DEBUG
#Preview("Zoomable receipt") {
    ZoomableImageView(image: SampleReceiptImage.make(index: 0))
        .background(Color(.systemBackground))
}
#endif
