import Foundation
import UIKit
import Vision

/// Reads the text off a receipt image.
///
/// Responsibilities:
/// - Run Vision's text recognition and return the recognised lines as plain text.
///
/// ## Settings, and why
/// `en-US` only. Vision has no Hebrew at any revision, and measurement showed extra
/// languages give no benefit for digits while costing about 60% more time — the amounts are
/// the same glyphs whatever the receipt's language, so nothing here depends on reading
/// words.
///
/// `usesLanguageCorrection` is off. Correction exists to fix words and can only damage
/// digits; in testing it introduced a stray apostrophe into otherwise clean output.
struct ReceiptTextRecognizer: Sendable {

    private static let languages = ["en-US"]

    /// Recognised text, one observation per line, or `nil` when nothing was found.
    func recognizeText(in image: UIImage) throws -> String? {
        guard let cgImage = image.cgImage else { throw StorageError.imageHasNoBitmap }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Self.languages
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
