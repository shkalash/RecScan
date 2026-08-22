import Foundation

/// Finds the dates printed on a receipt.
///
/// Responsibilities:
/// - Scan text for dates and rank them by how certain the reading is.
///
/// ## Why numeric dates are scanned here rather than left to `NSDataDetector`
/// Measured, not assumed. `NSDataDetector` handles prose well, but on numeric dates it:
///
/// | Input | Result on an `en_US` system |
/// |---|---|
/// | `21/08/2026` | 21 Aug — correct, 21 cannot be a month |
/// | `05/06/2026` | 6 May — **silently** resolved by system locale, no signal that the other reading exists |
/// | `31/08/2026` inside a longer line | mis-parsed entirely |
/// | `14:32` with no date | **today**, which is the exact wrong answer here |
///
/// The locale cannot be overridden — the detector has no `locale` property — so an
/// Israeli phone reads a US receipt wrong and says nothing about it. Numeric dates are
/// therefore scanned here, where ambiguity can be detected and *reported*, and the
/// detector is used only for month-name dates, which it is good at and which cannot be
/// ambiguous. Filtering its matches to ones containing a letter keeps the two apart and
/// drops the time-only case that resolves to today.
enum ReceiptDateParser {

    /// `d/m/y`, `d.m.y`, `d-m-y`, and the ISO `y-m-d`. Two- or four-digit years.
    private static let numericPattern = #"\b(\d{1,4})[./-](\d{1,2})[./-](\d{2,4})\b"#

    /// Receipts older than this are assumed to be a misread rather than a real purchase.
    private static let maximumAgeInYears = 20

    /// Which component comes first when a numeric date could be read either way.
    enum Order: Sendable {
        case dayFirst
        case monthFirst
    }

    // MARK: - Entry point

    /// Dates found in `text`, most trustworthy first.
    ///
    /// - Parameter order: how to read an ambiguous numeric date. Pass `nil` to infer it
    ///   from the text's own script and currency, falling back to the device's locale.
    static func candidates(
        in text: String?,
        order: Order? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DateCandidate] {
        guard let text, !text.isEmpty else { return [] }

        let preferred = order ?? inferredOrder(for: text)
        var found = numericCandidates(in: text, preferring: preferred, calendar: calendar)
        found += monthNameCandidates(in: text)

        // Plausibility is checked once, at the end, so every source is held to it: a
        // receipt cannot be from the future, and one from decades ago is a misread.
        let earliest = calendar.date(byAdding: .year, value: -maximumAgeInYears, to: now) ?? .distantPast
        let plausible = found.filter { $0.date <= now && $0.date >= earliest }

        // Stable sort by confidence: within a tier the order of appearance survives,
        // and the date printed first on a receipt is usually the transaction date.
        let ranked = plausible.enumerated()
            .sorted { lhs, rhs in
                lhs.element.confidence == rhs.element.confidence
                    ? lhs.offset < rhs.offset
                    : lhs.element.confidence < rhs.element.confidence
            }
            .map(\.element)

        return deduplicated(ranked)
    }

    /// The single best reading, or `nil` when the text holds no usable date.
    static func bestGuess(
        in text: String?,
        order: Order? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateCandidate? {
        candidates(in: text, order: order, now: now, calendar: calendar).first
    }

    // MARK: - Reading order

    /// Works out day-first or month-first from the document itself.
    ///
    /// The document beats the device: a US receipt read on an Israeli phone is still a US
    /// receipt. Only when the text says nothing does the locale get a vote.
    static func inferredOrder(for text: String) -> Order {
        if text.contains(where: \.isHebrewScript) || text.contains(Self.shekelSign) {
            return .dayFirst
        }
        return localeOrder()
    }

    private static let shekelSign: Character = "₪"

    /// Day-first or month-first according to how the device itself writes dates.
    static func localeOrder(locale: Locale = .current) -> Order {
        guard let template = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale),
              let day = template.firstIndex(of: "d"),
              let month = template.firstIndex(of: "M")
        else { return .dayFirst }
        return day < month ? .dayFirst : .monthFirst
    }

    // MARK: - Numeric dates

    private static func numericCandidates(
        in text: String,
        preferring preferred: Order,
        calendar: Calendar
    ) -> [DateCandidate] {
        guard let regex = try? NSRegularExpression(pattern: numericPattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        return matches.flatMap { match -> [DateCandidate] in
            let matched = ns.substring(with: match.range)
            let parts = (1...3).compactMap { index -> Int? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : Int(ns.substring(with: range))
            }
            guard parts.count == 3 else { return [] }
            return readings(of: parts, matched: matched, preferring: preferred, calendar: calendar)
        }
    }

    /// Every way the three numbers could legitimately be read.
    private static func readings(
        of parts: [Int],
        matched: String,
        preferring preferred: Order,
        calendar: Calendar
    ) -> [DateCandidate] {
        let (first, second, third) = (parts[0], parts[1], parts[2])

        // A four-digit or clearly-out-of-range leading number can only be a year.
        if first > 31 {
            return make(year: first, month: second, day: third, matched: matched,
                        confidence: .unambiguous, calendar: calendar).map { [$0] } ?? []
        }

        let year = normalisedYear(third)
        let dayFirst = make(year: year, month: second, day: first, matched: matched,
                            confidence: .unambiguous, calendar: calendar)
        let monthFirst = make(year: year, month: first, day: second, matched: matched,
                              confidence: .unambiguous, calendar: calendar)

        // Only one reading forms a real date -- 21/08 cannot be a month of 21 -- so the
        // receipt has settled it and no ambiguity needs reporting.
        switch (dayFirst, monthFirst) {
        case (.some(let only), .none): return [only]
        case (.none, .some(let only)): return [only]
        case (.none, .none): return []
        case (.some(let day), .some(let month)):
            let ordered = preferred == .dayFirst ? [day, month] : [month, day]
            // Both are real dates, so both are offered: the preferred reading leads and
            // the other is one tap away rather than lost.
            return [
                DateCandidate(date: ordered[0].date, text: matched, confidence: .inferredOrder),
                DateCandidate(date: ordered[1].date, text: matched, confidence: .alternativeOrder)
            ]
        }
    }

    private static func make(
        year: Int,
        month: Int,
        day: Int,
        matched: String,
        confidence: DateCandidate.Confidence,
        calendar: Calendar
    ) -> DateCandidate? {
        guard (1...12).contains(month), day >= 1 else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        // Midday, so a timezone shift cannot roll the receipt onto the previous day.
        components.hour = 12

        guard let date = calendar.date(from: components),
              // `date(from:)` happily rolls 31 April into 1 May; comparing back catches it.
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month
        else { return nil }

        return DateCandidate(date: date, text: matched, confidence: confidence)
    }

    /// `26` means 2026. Receipts are recent, and no till prints 1926.
    private static func normalisedYear(_ value: Int) -> Int {
        value < 100 ? 2000 + value : value
    }

    // MARK: - Month-name dates

    /// Prose dates, which `NSDataDetector` reads well and which cannot be ambiguous.
    ///
    /// Matches without a letter are dropped: those are the numeric and time-only cases,
    /// and the time-only one resolves to today, which is precisely the answer this whole
    /// feature exists to avoid.
    private static func monthNameCandidates(in text: String) -> [DateCandidate] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return [] }

        let ns = text as NSString
        return detector
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                guard let date = match.date else { return nil }
                let matched = ns.substring(with: match.range)
                guard matched.contains(where: \.isLetter) else { return nil }
                return DateCandidate(date: date, text: matched, confidence: .unambiguous)
            }
    }

    // MARK: - Tidying

    /// Drops repeats, keeping the most confident reading of each distinct day.
    private static func deduplicated(_ candidates: [DateCandidate]) -> [DateCandidate] {
        var seen: Set<Date> = []
        return candidates.filter { seen.insert($0.date).inserted }
    }
}

private extension Character {
    /// Hebrew block. Used as a signal that the document is Israeli, and so day-first.
    var isHebrewScript: Bool {
        unicodeScalars.contains { (0x0590...0x05FF).contains(Int($0.value)) }
    }
}
