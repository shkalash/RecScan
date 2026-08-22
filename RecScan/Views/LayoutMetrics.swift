import CoreGraphics

/// Layout constants shared by the app's views.
///
/// Responsibilities:
/// - Keep spacing, sizing and corner radii consistent and adjustable in one place.
enum LayoutMetrics {

    enum Grid {
        /// Smallest acceptable tile width; the adaptive grid fits as many as
        /// will fit at or above this width. Sized for roughly four per row on a
        /// standard iPhone.
        static let minimumItemWidth: CGFloat = 84
        static let itemSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
        static let cornerRadius: CGFloat = 10
        static let selectionBorderWidth: CGFloat = 3
        static let selectionBadgePadding: CGFloat = 6

        /// The date-and-amount pill along the bottom of a tile.
        enum Pill {
            static let padding: CGFloat = 4
            static let horizontalInset: CGFloat = 6
            static let verticalInset: CGFloat = 3
            /// Between the date line and the amount line.
            static let spacing: CGFloat = 1
            static let cornerRadius: CGFloat = 6
            /// Lets a long amount shrink rather than truncate on a narrow tile.
            static let minimumScale: CGFloat = 0.7
        }
    }

    enum Detail {
        static let imageCornerRadius: CGFloat = 12
        static let minimumZoomScale: CGFloat = 1
        static let maximumZoomScale: CGFloat = 6
        static let doubleTapZoomScale: CGFloat = 3
    }

    enum CategoryPicker {
        /// Wide enough that category names are not truncated in the popover.
        static let width: CGFloat = 320

        /// A `List` has no intrinsic height, so inside a popover it collapses to a
        /// single row. The height is therefore computed from the row count and clamped,
        /// rather than left to the container to infer.
        static let rowHeight: CGFloat = 44
        /// The text field row plus section insets, which are not part of the row count.
        static let chromeHeight: CGFloat = 96
        static let minimumHeight: CGFloat = 320
        /// Kept clear of the screen edges on the smallest supported device.
        static let maximumHeight: CGFloat = 480
    }

    enum Suggestions {
        static let spacing: CGFloat = 8
        static let chipPaddingX: CGFloat = 12
        static let chipPaddingY: CGFloat = 6
        static let chipIconSpacing: CGFloat = 4
    }

    enum Review {
        /// Small enough that the fields the sheet exists to fill stay above the fold.
        static let thumbnailHeight: CGFloat = 140
        static let zoomBadgePadding: CGFloat = 6
    }

    enum Form {
        static let noteEditorMinimumHeight: CGFloat = 96
    }

    enum Placeholder {
        static let iconSize: CGFloat = 28
    }
}
