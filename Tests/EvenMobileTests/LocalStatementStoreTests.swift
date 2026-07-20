import XCTest
@testable import EvenMobile
import HouseholdCore

@MainActor
final class LocalStatementStoreTests: XCTestCase {
    func testImportDeduplicatesAndPersistsInSecureStore() throws {
        let persistence = InMemoryStatementPersistence()

        let csv = """
        Date;Counterparty;Amount;Description
        16/07/2026;Water Company;-42,50;Monthly water bill
        """.data(using: .utf8)!

        let store = LocalStatementStore(persistence: persistence)
        XCTAssertEqual(try store.importStatement(data: csv, source: "water.csv"), 1)
        XCTAssertEqual(try store.importStatement(data: csv, source: "water.csv"), 0)
        XCTAssertEqual(store.transactions.count, 1)

        let reloaded = LocalStatementStore(persistence: persistence)
        XCTAssertEqual(reloaded.transactions.count, 1)
        XCTAssertEqual(reloaded.transactions.first?.counterparty, "Water Company")
    }

    func testMigratesExistingStatementFromLegacyDefaults() throws {
        let suite = "even.local-statement.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = InMemoryStatementPersistence()
        let transaction = BankTransaction(
            bookingDate: Date(timeIntervalSince1970: 1_784_332_800),
            amount: Decimal(string: "-42.50")!,
            counterparty: "Water Company",
            description: "Monthly water bill",
            source: "legacy.csv"
        )
        let data = try JSONEncoder().encode(LegacyState(transactions: [transaction], matches: [], lastImportAt: nil))
        defaults.set(data, forKey: "even.local-statement.v1")

        let store = LocalStatementStore(persistence: persistence, legacyDefaults: defaults)

        XCTAssertEqual(store.transactions, [transaction])
        XCTAssertNil(defaults.data(forKey: "even.local-statement.v1"))
        XCTAssertEqual(LocalStatementStore(persistence: persistence).transactions, [transaction])
    }

    func testDoesNotKeepImportInMemoryWhenSecureSaveFails() {
        let store = LocalStatementStore(persistence: FailingStatementPersistence())
        let csv = """
        Date;Counterparty;Amount;Description
        16/07/2026;Water Company;-42,50;Monthly water bill
        """.data(using: .utf8)!

        XCTAssertThrowsError(try store.importStatement(data: csv, source: "water.csv"))
        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertNil(store.lastImportAt)
    }
}

private final class InMemoryStatementPersistence: LocalStatementPersistence {
    private var data: Data?

    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
    func clear() throws { data = nil }
}

private struct FailingStatementPersistence: LocalStatementPersistence {
    func load() throws -> Data? { nil }
    func save(_ data: Data) throws { throw Failure() }
    func clear() throws {}

    private struct Failure: Error {}
}

private struct LegacyState: Codable {
    var transactions: [BankTransaction]
    var matches: [BankTransactionMatch]
    var lastImportAt: Date?
}
