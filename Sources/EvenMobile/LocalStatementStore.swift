import Foundation
import Observation
import EvenCore
import HouseholdCore

protocol LocalStatementPersistence {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func clear() throws
}

struct KeychainStatementPersistence: LocalStatementPersistence {
    private let store = KeychainDataStore(
        service: "com.umuryavuz.even.statement",
        account: "statement-and-matches.v1"
    )

    func load() throws -> Data? { try store.load() }
    func save(_ data: Data) throws { try store.save(data) }
    func clear() throws { try store.clear() }
}

enum LocalStatementStoreError: Error, LocalizedError {
    case unreadable
    case storage(Error)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The local statement could not be read."
        case let .storage(error):
            return (error as? LocalizedError)?.errorDescription ?? "Secure local storage is unavailable."
        }
    }
}

/// Device-local, read-only statement data. It deliberately has no API client:
/// imports and reconciliation decisions are stored in the device Keychain,
/// never in the household API or a bank-provider credential store.
@MainActor
@Observable
final class LocalStatementStore {
    private struct StoredState: Codable {
        var transactions: [BankTransaction]
        var matches: [BankTransactionMatch]
        var lastImportAt: Date?
    }

    private static let legacyStorageKey = "even.local-statement.v1"
    private let persistence: LocalStatementPersistence

    private(set) var transactions: [BankTransaction]
    private(set) var matches: [BankTransactionMatch]
    private(set) var lastImportAt: Date?

    init(persistence: LocalStatementPersistence = KeychainStatementPersistence(),
         legacyDefaults: UserDefaults = .standard) {
        self.persistence = persistence
        let secureData: Data?
        do {
            secureData = try persistence.load()
        } catch {
            secureData = nil
        }

        if let secureData,
           let state = try? JSONDecoder().decode(StoredState.self, from: secureData) {
            transactions = state.transactions
            matches = state.matches
            lastImportAt = state.lastImportAt
            return
        }

        if let data = legacyDefaults.data(forKey: Self.legacyStorageKey),
           let state = try? JSONDecoder().decode(StoredState.self, from: data) {
            transactions = state.transactions
            matches = state.matches
            lastImportAt = state.lastImportAt
            if (try? persist()) != nil {
                legacyDefaults.removeObject(forKey: Self.legacyStorageKey)
            }
            return
        }

        transactions = []
        matches = []
        lastImportAt = nil
    }

    var outgoingTransactions: [BankTransaction] {
        transactions.filter(\.isOutgoing).sorted { $0.bookingDate > $1.bookingDate }
    }

    var confirmedMatchCount: Int {
        matches.filter { $0.status == .confirmed }.count
    }

    var unmatchedOutgoingCount: Int {
        let confirmedTransactionIDs = Set(matches.filter { $0.status == .confirmed }.map(\.transactionID))
        return outgoingTransactions.filter { !confirmedTransactionIDs.contains($0.id) }.count
    }

    func suggestions(for drafts: [Draft]) -> [BankPaymentMatchSuggestion] {
        let obligations = drafts.compactMap(paymentObligation)
        let confirmedObligationIDs = Set(matches.filter { $0.status == .confirmed }.map(\.draftID))
        let confirmedTransactionIDs = Set(matches.filter { $0.status == .confirmed }.map(\.transactionID))
        let dismissedPairs = Set(matches.filter { $0.status == .dismissed }.map(pairKey))
        return BankingReconciliation.suggestions(
            obligations: obligations,
            transactions: transactions,
            confirmedObligationIDs: confirmedObligationIDs,
            confirmedTransactionIDs: confirmedTransactionIDs,
            dismissedPairs: dismissedPairs
        )
    }

    func confirmedMatch(for draftID: UUID) -> BankTransactionMatch? {
        matches
            .filter { $0.draftID == draftID && $0.status == .confirmed }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func transaction(id: UUID) -> BankTransaction? {
        transactions.first { $0.id == id }
    }

    @discardableResult
    func importStatement(data: Data, source: String) throws -> Int {
        let imported = try BankStatementCSVImporter.parse(data: data, source: source)
        let knownFingerprints = Set(transactions.map(\.fingerprint))
        let newTransactions = imported.filter { !knownFingerprints.contains($0.fingerprint) }
        try applyPersistedChange {
            transactions.append(contentsOf: newTransactions)
            lastImportAt = Date()
        }
        return newTransactions.count
    }

    func confirm(_ suggestion: BankPaymentMatchSuggestion) throws {
        try applyPersistedChange {
            matches.removeAll {
                $0.draftID == suggestion.obligationID || $0.transactionID == suggestion.transactionID
            }
            matches.append(BankTransactionMatch(
                draftID: suggestion.obligationID,
                transactionID: suggestion.transactionID,
                confidence: suggestion.confidence,
                status: .confirmed
            ))
        }
    }

    func dismiss(_ suggestion: BankPaymentMatchSuggestion) throws {
        try applyPersistedChange {
            matches.removeAll {
                $0.draftID == suggestion.obligationID && $0.transactionID == suggestion.transactionID
            }
            matches.append(BankTransactionMatch(
                draftID: suggestion.obligationID,
                transactionID: suggestion.transactionID,
                confidence: suggestion.confidence,
                status: .dismissed
            ))
        }
    }

    func clear() throws {
        let previousTransactions = transactions
        let previousMatches = matches
        let previousLastImportAt = lastImportAt
        transactions = []
        matches = []
        lastImportAt = nil
        do {
            try persistence.clear()
        } catch {
            transactions = previousTransactions
            matches = previousMatches
            lastImportAt = previousLastImportAt
            throw LocalStatementStoreError.storage(error)
        }
    }

    private func paymentObligation(_ draft: Draft) -> BankPaymentObligation? {
        guard draft.status == .pending, let amountCents = draft.amountCents, amountCents > 0 else {
            return nil
        }
        return BankPaymentObligation(
            id: draft.id,
            title: draft.title.isEmpty ? draft.subject : draft.title,
            amount: Decimal(amountCents) / 100,
            referenceDate: dueDate(from: draft.dueOn),
            searchText: [draft.fromLabel, draft.subject, draft.sourceFrom ?? ""].joined(separator: " ")
        )
    }

    private func persist() throws {
        let state = StoredState(transactions: transactions, matches: matches, lastImportAt: lastImportAt)
        guard let data = try? JSONEncoder().encode(state) else {
            throw LocalStatementStoreError.unreadable
        }
        do {
            try persistence.save(data)
        } catch {
            throw LocalStatementStoreError.storage(error)
        }
    }

    private func applyPersistedChange(_ change: () -> Void) throws {
        let previousTransactions = transactions
        let previousMatches = matches
        let previousLastImportAt = lastImportAt
        change()
        do {
            try persist()
        } catch {
            transactions = previousTransactions
            matches = previousMatches
            lastImportAt = previousLastImportAt
            throw error
        }
    }

    private func pairKey(_ match: BankTransactionMatch) -> String {
        "\(match.draftID.uuidString)-\(match.transactionID.uuidString)"
    }

    private func dueDate(from rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        return Self.dayFormatter.date(from: rawValue)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
