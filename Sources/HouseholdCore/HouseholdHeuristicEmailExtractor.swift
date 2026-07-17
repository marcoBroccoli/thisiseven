import Foundation

public struct HouseholdHeuristicEmailExtractor: EmailExtractor {
    private let now: Date
    private let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.now = now
        self.calendar = calendar
    }

    public func extract(from email: SourceEmail, household: HouseholdContext) async throws -> ExtractionResult {
        let text = "\(email.subject) \(email.bodyPreview) \(email.from)"
        let lowercased = text.lowercased()
        let area = suggestedArea(for: lowercased, household: household)
        let amount = firstAmount(in: text)
        let dueDate = dueDate(from: lowercased)
        let evidence = evidenceSnippets(email: email, amount: amount, dueDate: dueDate, area: area)
        let confidence = confidence(area: area, amount: amount, dueDate: dueDate, lowercased: lowercased)

        return ExtractionResult(
            title: email.subject,
            dueDate: dueDate,
            amount: amount,
            suggestedOwnerID: nil,
            areaID: area?.id,
            evidence: evidence,
            confidence: confidence
        )
    }

    private func suggestedArea(for text: String, household: HouseholdContext) -> HouseholdArea? {
        let areaScores = household.areas.map { area in
            (area, score(area: area, text: text))
        }
        return areaScores.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil }
    }

    private func score(area: HouseholdArea, text: String) -> Int {
        let name = area.name.lowercased()
        let keywords: [String]

        if name.contains("util") {
            keywords = ["bill", "utility", "utilities", "electric", "electricity", "energy", "gas", "water", "internet", "broadband", "wifi", "phone"]
        } else if name.contains("sub") {
            keywords = ["subscription", "renewal", "renew", "membership", "insurance", "streaming", "plan"]
        } else if name.contains("admin") {
            keywords = ["form", "school", "appointment", "dentist", "doctor", "tax", "maintenance", "repair", "delivery", "document"]
        } else {
            keywords = [name]
        }

        return keywords.reduce(0) { score, keyword in
            score + (text.contains(keyword) ? 1 : 0)
        }
    }

    private func firstAmount(in text: String) -> Decimal? {
        let pattern = #"(?i)(?:€|\$|eur|usd|amount:?|total:?)\s*([0-9]+(?:[.,][0-9]{1,2})?)|([0-9]+[.,][0-9]{2})"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { continue }
            let normalized = text[swiftRange].replacingOccurrences(of: ",", with: ".")
            if let amount = Decimal(string: normalized) {
                return amount
            }
        }

        return nil
    }

    private func dueDate(from text: String) -> Date? {
        if text.contains("due tomorrow") || text.contains("by tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        }

        if text.contains("due today") || text.contains("by today") {
            return startOfToday
        }

        if let days = firstCapture(
            in: text,
            pattern: #"(?:due|by|before|in)\s+(?:in\s+)?([0-9]{1,2})\s+days?"#
        ).flatMap(Int.init) {
            return calendar.date(byAdding: .day, value: days, to: startOfToday)
        }

        if text.contains("end of month") || text.contains("month end") {
            return endOfCurrentMonth
        }

        if let absoluteDate = absoluteDate(in: text) {
            return absoluteDate
        }

        let weekdayNames = calendar.weekdaySymbols.map { $0.lowercased() }
        for (index, weekday) in weekdayNames.enumerated() {
            let nextWeekPhrases = ["due next \(weekday)", "by next \(weekday)", "before next \(weekday)", "on next \(weekday)"]
            if nextWeekPhrases.contains(where: text.contains) {
                return nextDate(weekday: index + 1, forceFollowingWeek: true)
            }

            let weekdayPhrases = ["due \(weekday)", "by \(weekday)", "before \(weekday)", "on \(weekday)"]
            if weekdayPhrases.contains(where: text.contains) {
                return nextDate(weekday: index + 1)
            }
        }

        return nil
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: now)
    }

    private var endOfCurrentMonth: Date? {
        guard let month = calendar.dateInterval(of: .month, for: startOfToday) else { return nil }
        return calendar.startOfDay(for: month.end.addingTimeInterval(-1))
    }

    private func nextDate(weekday: Int, forceFollowingWeek: Bool = false) -> Date? {
        var components = DateComponents()
        components.weekday = weekday
        guard let nextDate = calendar.nextDate(
            after: startOfToday,
            matching: components,
            matchingPolicy: .nextTime
        ).map(calendar.startOfDay) else {
            return nil
        }

        guard forceFollowingWeek else { return nextDate }
        return calendar.date(byAdding: .day, value: 7, to: nextDate)
    }

    private func absoluteDate(in text: String) -> Date? {
        let monthPattern = #"jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"#

        if let match = captures(
            in: text,
            pattern: #"(?:due|by|before|on)\s+(?:on\s+)?([0-9]{1,2})(?:st|nd|rd|th)?\s+(\#(monthPattern))(?:\s*,?\s*([0-9]{4}))?"#
        ), match.count >= 3,
           let day = Int(match[0]) {
            return date(day: day, monthName: match[1], yearText: match[2])
        }

        if let match = captures(
            in: text,
            pattern: #"(?:due|by|before|on)\s+(?:on\s+)?(\#(monthPattern))\s+([0-9]{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*([0-9]{4}))?"#
        ), match.count >= 3,
           let day = Int(match[1]) {
            return date(day: day, monthName: match[0], yearText: match[2])
        }

        if let match = captures(
            in: text,
            pattern: #"(?:due|by|before|on)\s+(?:on\s+)?([0-9]{1,2})[/-]([0-9]{1,2})(?:[/-]([0-9]{2,4}))?"#
        ), match.count >= 3,
           let day = Int(match[0]),
           let month = Int(match[1]) {
            return date(day: day, month: month, yearText: match[2])
        }

        return nil
    }

    private func date(day: Int, monthName: String, yearText: String) -> Date? {
        let symbols = calendar.monthSymbols + calendar.shortMonthSymbols
        guard let month = symbols.firstIndex(where: { $0.lowercased() == monthName.lowercased() }).map({ ($0 % 12) + 1 }) else {
            return nil
        }
        return date(day: day, month: month, yearText: yearText)
    }

    private func date(day: Int, month: Int, yearText: String) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let currentYear = calendar.component(.year, from: startOfToday)
        let parsedYear = Int(yearText)
        let year: Int
        if let parsedYear {
            year = parsedYear < 100 ? 2_000 + parsedYear : parsedYear
        } else {
            year = currentYear
        }

        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        guard let candidate = calendar.date(from: components).map(calendar.startOfDay) else { return nil }

        if parsedYear == nil, candidate < startOfToday {
            return calendar.date(byAdding: .year, value: 1, to: candidate)
        }
        return candidate
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        captures(in: text, pattern: pattern)?.first
    }

    private func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        return (1..<match.numberOfRanges).map { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: text) else {
                return ""
            }
            return String(text[swiftRange])
        }
    }

    private func confidence(area: HouseholdArea?, amount: Decimal?, dueDate: Date?, lowercased: String) -> Double {
        var score = 0.42
        if area != nil { score += 0.12 }
        if amount != nil { score += 0.14 }
        if dueDate != nil { score += 0.18 }
        if lowercased.contains("bill") || lowercased.contains("invoice") || lowercased.contains("renew") { score += 0.08 }
        return min(score, 0.92)
    }

    private func evidenceSnippets(email: SourceEmail, amount: Decimal?, dueDate: Date?, area: HouseholdArea?) -> [String] {
        var evidence = [email.bodyPreview].filter { !$0.isEmpty }
        if let amount {
            evidence.append("Detected amount: \(amount)")
        }
        if dueDate != nil {
            evidence.append("Detected due date from email text")
        }
        if let area {
            evidence.append("Suggested area: \(area.name)")
        }
        return evidence
    }
}
