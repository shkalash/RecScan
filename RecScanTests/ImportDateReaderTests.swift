import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import RecScan

@Suite("Import capture dates")
struct ImportDateReaderTests {

    /// A JPEG carrying a real EXIF `DateTimeOriginal`.
    private func imageData(withEXIFDate date: Date?) -> Data {
        let image = TestImage.solid(width: 60, height: 90)
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        )!

        var properties: [CFString: Any] = [:]
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = .current
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: formatter.string(from: date)
            ] as CFDictionary
        }

        CGImageDestinationAddImage(destination, image.cgImage!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test("An EXIF capture date is read and trusted")
    func readsExifDate() throws {
        let taken = TestCalendar.date(year: 2026, month: 7, day: 4, hour: 15)

        let result = ImportDateReader.captureDate(from: imageData(withEXIFDate: taken))

        // Compared to the second: EXIF has no sub-second component.
        #expect(abs(result.date.timeIntervalSince(taken)) < 1)
        #expect(result.isCertain)
    }

    @Test("Without EXIF, the file's date is used and still trusted")
    func fallsBackToFileDate() {
        let fileDate = TestCalendar.date(year: 2026, month: 6, day: 1)

        let result = ImportDateReader.captureDate(from: imageData(withEXIFDate: nil), fileDate: fileDate)

        #expect(result.date == fileDate)
        #expect(result.isCertain)
    }

    @Test("With nothing to go on, today is used and flagged as uncertain")
    func fallsBackToTodayUncertain() {
        let now = TestCalendar.date(year: 2026, month: 8, day: 21)

        let result = ImportDateReader.captureDate(from: imageData(withEXIFDate: nil), fileDate: nil, now: now)

        #expect(result.date == now)
        // The flag is what makes the receipt get badged instead of silently mis-dated.
        #expect(!result.isCertain)
    }

    @Test("EXIF wins over the file's date")
    func exifBeatsFileDate() {
        let taken = TestCalendar.date(year: 2026, month: 7, day: 4, hour: 15)
        let fileDate = TestCalendar.date(year: 2026, month: 8, day: 20)

        let result = ImportDateReader.captureDate(from: imageData(withEXIFDate: taken), fileDate: fileDate)

        // A photo copied between devices carries a recent file date and an old shutter
        // time; the shutter time is the receipt's date.
        #expect(abs(result.date.timeIntervalSince(taken)) < 1)
    }

    @Test("Data that is not an image yields no date rather than crashing")
    func handlesGarbage() {
        let result = ImportDateReader.captureDate(from: Data("not an image".utf8))

        #expect(!result.isCertain)
    }
}
