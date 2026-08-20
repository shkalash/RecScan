import Foundation

/// Failures raised while generating an export.
enum PDFBuildError: Error, Equatable {
    /// The caller asked for a PDF of nothing.
    case noReceiptsSelected
}
