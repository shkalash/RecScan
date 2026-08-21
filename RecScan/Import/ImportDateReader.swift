import Foundation
import ImageIO

/// Works out when a photo was taken.
///
/// Responsibilities:
/// - Read a capture date out of image metadata, and say how much to trust it.
///
/// ## Order, and why
/// EXIF `DateTimeOriginal` is the moment the shutter fired — the only value that is
/// actually the receipt's date. Failing that, the file's creation date is usually close
/// enough to be a useful starting point. Failing both, today is a placeholder and is
/// reported as uncertain so the receipt gets flagged rather than silently mis-dated.
enum ImportDateReader {

    /// A date and whether it came from the file or was assumed.
    struct Result: Equatable {
        let date: Date
        let isCertain: Bool
    }

    /// EXIF writes dates in the local time of the camera, with no zone. Parsing them as
    /// UTC would shift receipts across midnight for anyone east or west of Greenwich.
    private static let exifFormat = "yyyy:MM:dd HH:mm:ss"

    static func captureDate(from data: Data, fileDate: Date? = nil, now: Date = Date()) -> Result {
        if let exif = exifDate(from: data) {
            return Result(date: exif, isCertain: true)
        }
        if let fileDate {
            return Result(date: fileDate, isCertain: true)
        }
        return Result(date: now, isCertain: false)
    }

    /// `DateTimeOriginal`, falling back to the TIFF `DateTime` some scanners write.
    static func exifDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let candidates = [
            exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
            tiff?[kCGImagePropertyTIFFDateTime] as? String
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppConstants.Format.posixLocaleIdentifier)
        formatter.dateFormat = exifFormat
        formatter.timeZone = .current

        for candidate in candidates.compactMap({ $0 }) {
            if let date = formatter.date(from: candidate) { return date }
        }
        return nil
    }
}
