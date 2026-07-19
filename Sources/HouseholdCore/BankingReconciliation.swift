import Foundation

public struct BankTransaction: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var bookingDate: Date
    public var amount: Decimal
    public var counterparty: String
    public var description: String
    public var source: String
    public var fingerprint: String

    public init(
        id: UUID = UUID(),
        bookingDate: Date,
        amount: Decimal,
        counterparty: String,
        description: String,
        source: String,
        fingerprint: String? = nil
    ) {
        self.id = id
        self.bookingDate = bookingDate
        self.amount = amount
        self.counterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fingerprint = fingerprint ?? Self.makeFingerprint(
            bookingDate: bookingDate,
            amount: amount,
            counterparty: counterparty,
            description: description,
            source: source
        )
    }

    public var isOutgoing: Bool {
        amount < 0
    }

    public var displayName: String {
        counterparty.isEmpty ? description : counterparty
    }

    public static func makeFingerprint(
        bookingDate: Date,
        amount: Decimal,
        counterparty: String,
        description: String,
        source: String
    ) -> String {
        let day = Int(bookingDate.timeIntervalSince1970 / 86_400)
        let amountText = NSDecimalNumber(decimal: amount).stringValue
        let normalized = [counterparty, description, source]
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
        return "\(day)|\(amountText)|\(normalized)"
    }
}

public enum BankMatchStatus: String, Equatable, Codable, CaseIterable, Sendable {
    case confirmed
    case dismissed
}

public struct BankTransactionMatch: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var draftID: UUID
    public var transactionID: UUID
    public var confidence: Double
    public var status: BankMatchStatus
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        draftID: UUID,
        transactionID: UUID,
        confidence: Double,
        status: BankMatchStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.draftID = draftID
        self.transactionID = transactionID
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
    }
}

public struct BankMatchSuggestion: Identifiable, Equatable, Sendable {
    public var id: String { "\(draftID.uuidString)-\(transactionID.uuidString)" }
    public var draftID: UUID
    public var transactionID: UUID
    public var confidence: Double
    public var reasons: [String]

    public init(draftID: UUID, transactionID: UUID, confidence: Double, reasons: [String]) {
        self.draftID = draftID
        self.transactionID = transactionID
        self.confidence = confidence
        self.reasons = reasons
    }
}

public enum BankingReconciliation {
    public static func suggestions(
        drafts: [InboxDraft],
        transactions: [BankTransaction],
        storedMatches: [BankTransactionMatch]
    ) -> [BankMatchSuggestion] {
        let confirmedDraftIDs = Set(
            storedMatches
                .filter { $0.status == .confirmed }
                .map(\.draftID)
        )
        let confirmedTransactionIDs = Set(
            storedMatches
                .filter { $0.status == .confirmed }
                .map(\.transactionID)
        )
        let dismissedPairs = Set(
            storedMatches
                .filter { $0.status == .dismissed }
                .map { "\($0.draftID.uuidString)-\($0.transactionID.uuidString)" }
        )
        let eligibleTransactions = transactions.filter { transaction in
            transaction.isOutgoing && !confirmedTransactionIDs.contains(transaction.id)
        }

        return drafts.compactMap { draft in
            guard isReconciliationEligible(draft), !confirmedDraftIDs.contains(draft.id) else { return nil }

            let candidates = eligibleTransactions.compactMap { transaction -> BankMatchSuggestion? in
                let pairID = "\(draft.id.uuidString)-\(transaction.id.uuidString)"
                guard !dismissedPairs.contains(pairID) else { return nil }
                return score(draft: draft, transaction: transaction)
            }

            return candidates.max { left, right in
                if left.confidence == right.confidence {
                    return left.transactionID.uuidString < right.transactionID.uuidString
                }
                return left.confidence < right.confidence
            }
        }
        .sorted { left, right in
            if left.confidence == right.confidence {
                return left.draftID.uuidString < right.draftID.uuidString
            }
            return left.confidence > right.confidence
        }
    }

    private static func isReconciliationEligible(_ draft: InboxDraft) -> Bool {
        guard draft.amount != nil, draft.status != .rejected else { return false }
        return !((draft.triageState?.isClosed) ?? false)
            && !DraftSnoozeService.isCurrentlySnoozed(draft)
    }

    private static func score(draft: InboxDraft, transaction: BankTransaction) -> BankMatchSuggestion? {
        guard let amount = draft.amount else { return nil }

        let expected = absolute(amount)
        let actual = absolute(transaction.amount)
        let difference = absolute(expected - actual)
        let percentageTolerance = expected * Decimal(string: "0.02")!
        let tolerance = max(percentageTolerance, Decimal(string: "0.10")!)

        let amountScore: Double
        var reasons: [String]
        if difference == 0 {
            amountScore = 0.72
            reasons = ["Exact amount"]
        } else if difference <= tolerance {
            amountScore = 0.60
            reasons = ["Amount within tolerance"]
        } else if difference <= Decimal(2) {
            amountScore = 0.32
            reasons = ["Amount is close"]
        } else {
            return nil
        }

        var confidence = amountScore
        let sharedTerms = matchingTerms(draft: draft, transaction: transaction)
        if !sharedTerms.isEmpty {
            confidence += 0.20
            reasons.append("Shared detail: \(sharedTerms.prefix(2).joined(separator: ", "))")
        }

        let referenceDate = draft.dueDate ?? draft.source.receivedAt
        let dayDistance = abs(Calendar.current.dateComponents([.day], from: transaction.bookingDate, to: referenceDate).day ?? 99)
        if dayDistance <= 7 {
            confidence += 0.12
            reasons.append("Close to due date")
        } else if dayDistance <= 31 {
            confidence += 0.06
            reasons.append("Within the payment window")
        }

        guard confidence >= 0.55 else { return nil }
        return BankMatchSuggestion(
            draftID: draft.id,
            transactionID: transaction.id,
            confidence: min(confidence, 0.98),
            reasons: reasons
        )
    }

    private static func matchingTerms(draft: InboxDraft, transaction: BankTransaction) -> [String] {
        let draftTerms = terms(in: [draft.title, draft.source.from, draft.source.subject].joined(separator: " "))
        let transactionTerms = terms(in: [transaction.counterparty, transaction.description].joined(separator: " "))
        return Array(draftTerms.intersection(transactionTerms)).sorted()
    }

    private static func terms(in text: String) -> Set<String> {
        let ignored = Set(["bill", "invoice", "payment", "renewal", "monthly", "household", "your", "from", "with", "this", "that", "email", "example", "com"])
        let words = text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        return Set(words.filter { $0.count >= 4 && !ignored.contains($0) })
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}

public enum BankStatementCSVImportError: Error, Equatable, LocalizedError, Sendable {
    case unreadableText
    case missingHeader
    case missingAmountColumn
    case noValidTransactions

    public var errorDescription: String? {
        switch self {
        case .unreadableText:
            "The statement could not be read as a CSV text file."
        case .missingHeader:
            "The statement needs a header row with a date and amount column."
        case .missingAmountColumn:
            "The statement needs an amount column, or separate debit and credit columns."
        case .noValidTransactions:
            "No valid transactions were found in this statement."
        }
    }
}

public enum BankStatementCSVImporter {
    public static func parse(data: Data, source: String) throws -> [BankTransaction] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BankStatementCSVImportError.unreadableText
        }
        return try parse(text: text, source: source)
    }

    public static func parse(text: String, source: String) throws -> [BankTransaction] {
        let delimiter = preferredDelimiter(in: text)
        let rows = parseRows(text, delimiter: delimiter)
        guard let rawHeader = rows.first, !rawHeader.isEmpty else {
            throw BankStatementCSVImportError.missingHeader
        }

        let header = rawHeader.map(normalizedHeader)
        guard index(of: ["date", "booking date", "transaction date", "datum", "boekingsdatum"], in: header) != nil else {
            throw BankStatementCSVImportError.missingHeader
        }

        let amountIndex = index(of: ["amount", "bedrag", "transaction amount", "value"], in: header)
        let debitIndex = index(of: ["debit", "afschrijving", "withdrawal"], in: header)
        let creditIndex = index(of: ["credit", "bijschrijving", "deposit"], in: header)
        guard amountIndex != nil || debitIndex != nil || creditIndex != nil else {
            throw BankStatementCSVImportError.missingAmountColumn
        }

        guard let dateIndex = index(of: ["date", "booking date", "transaction date", "datum", "boekingsdatum"], in: header) else {
            throw BankStatementCSVImportError.missingHeader
        }

        let counterpartyIndex = index(of: ["counterparty", "counterparty name", "merchant", "payee", "name", "tegenpartij"], in: header)
        let descriptionIndex = index(of: ["description", "details", "memo", "reference", "payment reference", "omschrijving", "mededelingen"], in: header)

        let transactions = rows.dropFirst().compactMap { row -> BankTransaction? in
            guard let bookingDate = date(from: value(at: dateIndex, in: row)) else { return nil }
            guard let amount = amount(
                row: row,
                amountIndex: amountIndex,
                debitIndex: debitIndex,
                creditIndex: creditIndex
            ) else { return nil }

            let counterparty = counterpartyIndex.map { value(at: $0, in: row) } ?? ""
            let description = descriptionIndex.map { value(at: $0, in: row) } ?? ""
            return BankTransaction(
                bookingDate: bookingDate,
                amount: amount,
                counterparty: counterparty,
                description: description,
                source: source
            )
        }

        guard !transactions.isEmpty else {
            throw BankStatementCSVImportError.noValidTransactions
        }
        return transactions
    }

    private static func preferredDelimiter(in text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let candidates: [Character] = [";", ",", "\t"]
        return candidates.max { left, right in
            firstLine.filter { $0 == left }.count < firstLine.filter { $0 == right }.count
        } ?? ","
    }

    private static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == delimiter, !isQuoted {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                if row.contains(where: { !$0.isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func index(of candidates: [String], in header: [String]) -> Int? {
        header.firstIndex { candidates.contains($0) }
    }

    private static func value(at index: Int, in row: [String]) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    private static func amount(
        row: [String],
        amountIndex: Int?,
        debitIndex: Int?,
        creditIndex: Int?
    ) -> Decimal? {
        if let amountIndex, let amount = decimal(from: value(at: amountIndex, in: row)) {
            return amount
        }
        if let debitIndex, let debit = decimal(from: value(at: debitIndex, in: row)) {
            return debit < 0 ? debit : -debit
        }
        if let creditIndex, let credit = decimal(from: value(at: creditIndex, in: row)) {
            return credit < 0 ? -credit : credit
        }
        return nil
    }

    private static func decimal(from rawValue: String) -> Decimal? {
        let isParenthesized = rawValue.contains("(") && rawValue.contains(")")
        var value = String(rawValue.filter { "0123456789,.-+".contains($0) })
        guard value.contains(where: \.isNumber) else { return nil }

        let commaCount = value.filter { $0 == "," }.count
        let dotCount = value.filter { $0 == "." }.count
        if commaCount > 0 && dotCount > 0 {
            let decimalSeparator = max(value.lastIndex(of: ",")!, value.lastIndex(of: ".")!)
            var normalized = ""
            for index in value.indices {
                let character = value[index]
                if character == "," || character == "." {
                    if index == decimalSeparator {
                        normalized.append(".")
                    }
                } else {
                    normalized.append(character)
                }
            }
            value = normalized
        } else if commaCount > 0 {
            value = normalizedSingleSeparator(value, separator: ",")
        } else if dotCount > 1 {
            value = normalizedSingleSeparator(value, separator: ".")
        }

        guard var decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if isParenthesized, decimal > 0 {
            decimal = -decimal
        }
        return decimal
    }

    private static func normalizedSingleSeparator(_ value: String, separator: Character) -> String {
        guard let lastSeparator = value.lastIndex(of: separator) else { return value }
        let fractionalDigits = value[value.index(after: lastSeparator)...].filter(\.isNumber).count
        guard fractionalDigits > 0 && fractionalDigits <= 2 else {
            return value.replacingOccurrences(of: String(separator), with: "")
        }

        var result = ""
        for index in value.indices {
            let character = value[index]
            if character == separator {
                if index == lastSeparator {
                    result.append(".")
                }
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd", "dd-MM-yyyy", "dd/MM/yyyy", "yyyy/MM/dd", "dd.MM.yyyy", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return Calendar.current.startOfDay(for: date)
            }
        }

        return ISO8601DateFormatter().date(from: trimmed).map(Calendar.current.startOfDay)
    }
}
