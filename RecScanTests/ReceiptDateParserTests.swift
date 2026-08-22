import Foundation
import Testing
@testable import RecScan

/// A receipt's own printed date is the only trustworthy one, and reading it means
/// deciding day-first or month-first without being told. These fixtures are the shapes
/// that actually turn up on emailed receipts.
@Suite("Receipt date parsing")
struct ReceiptDateParserTests {

    /// Fixed, so "not in the future" and "not too old" are stable assertions.
    private let now = TestCalendar.date(year: 2026, month: 9, day: 1)
    private let calendar = TestCalendar.utcGregorian

    private func candidates(
        _ text: String,
        order: ReceiptDateParser.Order = .dayFirst
    ) -> [DateCandidate] {
        ReceiptDateParser.candidates(in: text, order: order, now: now, calendar: calendar)
    }

    private func ymd(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Unambiguous

    @Test("A day over 12 settles the order by itself")
    func dayOverTwelveIsUnambiguous() throws {
        let found = try #require(candidates("Date: 21/08/2026", order: .monthFirst).first)

        // Even told to prefer month-first: there is no month 21, so the receipt decides.
        #expect(ymd(found.date) == "2026-08-21")
        #expect(found.confidence == .unambiguous)
    }

    @Test("A month-first date with a day over 12 also settles itself")
    func monthFirstWithLargeDay() throws {
        let found = try #require(candidates("Date: 08/21/2026", order: .dayFirst).first)

        #expect(ymd(found.date) == "2026-08-21")
        #expect(found.confidence == .unambiguous)
    }

    @Test("An ISO date is read as written")
    func isoDate() throws {
        let found = try #require(candidates("2026-08-21 Total 52.30").first)

        #expect(ymd(found.date) == "2026-08-21")
        #expect(found.confidence == .unambiguous)
    }

    @Test("Dots and dashes work as separators")
    func separators() throws {
        #expect(ymd(try #require(candidates("21.08.2026").first).date) == "2026-08-21")
        #expect(ymd(try #require(candidates("21-08-2026").first).date) == "2026-08-21")
    }

    @Test("A two-digit year means this century")
    func twoDigitYear() throws {
        #expect(ymd(try #require(candidates("21/08/26").first).date) == "2026-08-21")
    }

    @Test("A month name is read without needing an order at all")
    func monthName() throws {
        let found = try #require(candidates("August 21, 2026  Total $52.30").first)

        #expect(ymd(found.date) == "2026-08-21")
        #expect(found.confidence == .unambiguous)
    }

    // MARK: - Ambiguity

    /// The case no parser can settle from the page: both readings are real dates.
    @Test("An ambiguous date offers both readings, preferred one first")
    func ambiguousOffersBoth() {
        let found = candidates("Date: 05/06/2026", order: .dayFirst)

        #expect(found.count == 2)
        #expect(ymd(found[0].date) == "2026-06-05")
        #expect(found[0].confidence == .inferredOrder)
        #expect(ymd(found[1].date) == "2026-05-06")
        #expect(found[1].confidence == .alternativeOrder)
    }

    @Test("Month-first flips which reading leads, keeping both")
    func ambiguousRespectsOrder() {
        let found = candidates("Date: 05/06/2026", order: .monthFirst)

        #expect(ymd(found[0].date) == "2026-05-06")
        #expect(ymd(found[1].date) == "2026-06-05")
    }

    // MARK: - Inferring the order from the document

    /// The document beats the device: a US receipt on an Israeli phone is still US.
    @Test("Hebrew text is read day-first")
    func hebrewImpliesDayFirst() {
        #expect(ReceiptDateParser.inferredOrder(for: "תאריך: 05/06/2026") == .dayFirst)
    }

    @Test("A shekel sign is read day-first")
    func shekelImpliesDayFirst() {
        #expect(ReceiptDateParser.inferredOrder(for: "TOTAL ₪52.30 05/06/2026") == .dayFirst)
    }

    @Test("A numeric date inside Hebrew text is still found")
    func hebrewReceipt() throws {
        let text = "חשבונית מס קבלה\nתאריך: 21/08/2026\nסה\"כ לתשלום 52.30"
        let found = try #require(ReceiptDateParser.candidates(in: text, now: now, calendar: calendar).first)

        #expect(ymd(found.date) == "2026-08-21")
    }

    // MARK: - Rejection

    /// The trap this whole feature exists to avoid: a bare time resolves to today.
    @Test("A time with no date yields nothing")
    func timeAloneIsNotADate() {
        #expect(candidates("Receipt printed 14:32").isEmpty)
    }

    @Test("A future date is rejected")
    func futureRejected() {
        #expect(candidates("Date: 21/12/2027").isEmpty)
    }

    @Test("A date from decades ago is rejected as a misread")
    func ancientRejected() {
        #expect(candidates("Ref 01/01/1995").isEmpty)
    }

    @Test("An impossible day is rejected rather than rolled forward")
    func impossibleDayRejected() {
        // Calendar arithmetic would happily turn 31 April into 1 May.
        #expect(candidates("31/04/2026").isEmpty)
    }

    @Test("Text with no dates yields nothing")
    func noDates() {
        #expect(candidates("TOTAL 52.30 THANK YOU").isEmpty)
        #expect(ReceiptDateParser.candidates(in: nil).isEmpty)
    }

    // MARK: - Several dates

    @Test("Several dates are all offered, earliest in the text first")
    func multipleDatesKeepTextOrder() {
        let found = candidates("Issued 01/08/2026 Due 31/08/2026")

        #expect(found.contains { self.ymd($0.date) == "2026-08-31" })
        #expect(found.contains { self.ymd($0.date) == "2026-08-01" })
    }

    @Test("The same date printed twice is offered once")
    func duplicatesCollapse() {
        let found = candidates("Date 21/08/2026 ... again 21/08/2026")

        #expect(found.count == 1)
    }

    @Test("The best guess is the most confident reading")
    func bestGuessPrefersCertainty() throws {
        // The ambiguous date comes first in the text; the certain one should still win.
        let found = try #require(
            ReceiptDateParser.bestGuess(in: "05/06/2026 and 21/08/2026", order: .dayFirst, now: now)
        )

        #expect(ymd(found.date) == "2026-08-21")
    }
}
