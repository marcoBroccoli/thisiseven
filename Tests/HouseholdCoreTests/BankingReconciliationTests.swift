import XCTest
@testable import HouseholdCore

final class BankingReconciliationTests: XCTestCase {
    func testCSVImporterParsesEuropeanAmountAndSemicolonDelimiter() throws {
        let csv = """
        Date;Counterparty;Amount;Description
        16/07/2026;Water Company;-42,50;Monthly water bill
        """

        let transactions = try BankStatementCSVImporter.parse(text: csv, source: "water.csv")

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].amount, Decimal(string: "-42.50"))
        XCTAssertEqual(transactions[0].counterparty, "Water Company")
        XCTAssertEqual(transactions[0].description, "Monthly water bill")
        XCTAssertEqual(transactions[0].source, "water.csv")
    }

    func testCSVImporterTurnsDebitColumnIntoOutgoingPayment() throws {
        let csv = """
        Booking Date,Counterparty,Debit,Credit
        2026-07-16,Insurance Services,129.99,
        2026-07-17,Employer,,2500.00
        """

        let transactions = try BankStatementCSVImporter.parse(text: csv, source: "statement.csv")

        XCTAssertEqual(transactions.map(\.amount), [Decimal(string: "-129.99"), Decimal(2500)])
        XCTAssertTrue(transactions[0].isOutgoing)
        XCTAssertFalse(transactions[1].isOutgoing)
    }

    func testReconciliationPrioritizesExactPaymentWithSharedTerms() {
        let dueDate = Date(timeIntervalSince1970: 1_784_332_800)
        let draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "water-email",
                subject: "Water bill due",
                from: "billing@water.example",
                receivedAt: dueDate.addingTimeInterval(-86_400),
                label: "Auto Household",
                bodyPreview: "Your water bill is due."
            ),
            title: "Pay water bill",
            dueDate: dueDate,
            amount: Decimal(string: "42.50"),
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.9,
            evidence: []
        )
        let matchingTransaction = BankTransaction(
            bookingDate: dueDate.addingTimeInterval(-86_400),
            amount: Decimal(string: "-42.50")!,
            counterparty: "Water Company",
            description: "Monthly water bill",
            source: "statement.csv"
        )
        let unrelatedTransaction = BankTransaction(
            bookingDate: dueDate,
            amount: Decimal(string: "-42.50")!,
            counterparty: "Coffee House",
            description: "Card payment",
            source: "statement.csv"
        )

        let suggestions = BankingReconciliation.suggestions(
            drafts: [draft],
            transactions: [unrelatedTransaction, matchingTransaction],
            storedMatches: []
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].transactionID, matchingTransaction.id)
        XCTAssertGreaterThan(suggestions[0].confidence, 0.9)
        XCTAssertTrue(suggestions[0].reasons.contains("Exact amount"))
    }

    func testGenericObligationAdapterReusesTheStatementScorer() {
        let dueDate = Date(timeIntervalSince1970: 1_784_332_800)
        let obligation = BankPaymentObligation(
            id: UUID(),
            title: "Pay water bill",
            amount: Decimal(string: "42.50")!,
            referenceDate: dueDate,
            searchText: "Water Company monthly invoice"
        )
        let transaction = BankTransaction(
            bookingDate: dueDate.addingTimeInterval(-86_400),
            amount: Decimal(string: "-42.50")!,
            counterparty: "Water Company",
            description: "Monthly payment",
            source: "statement.csv"
        )

        let suggestions = BankingReconciliation.suggestions(
            obligations: [obligation], transactions: [transaction]
        )

        XCTAssertEqual(suggestions.first?.obligationID, obligation.id)
        XCTAssertEqual(suggestions.first?.transactionID, transaction.id)
        XCTAssertGreaterThan(suggestions.first?.confidence ?? 0, 0.9)
    }

    func testLocalStateDeduplicatesTransactionsAndDefaultsNewFieldsForOlderData() throws {
        let transaction = BankTransaction(
            bookingDate: Date(timeIntervalSince1970: 1_784_332_800),
            amount: Decimal(-42),
            counterparty: "Water Company",
            description: "Bill",
            source: "statement.csv"
        )
        let duplicate = BankTransaction(
            bookingDate: transaction.bookingDate,
            amount: transaction.amount,
            counterparty: transaction.counterparty,
            description: transaction.description,
            source: transaction.source
        )
        var state = LocalHouseholdState()

        XCTAssertEqual(state.mergeBankTransactions([transaction, duplicate]), 1)
        XCTAssertEqual(state.bankTransactions.count, 1)

        let legacyData = Data("{\"drafts\":[]}".utf8)
        let legacyState = try JSONDecoder().decode(LocalHouseholdState.self, from: legacyData)
        XCTAssertEqual(legacyState.bankTransactions, [])
        XCTAssertEqual(legacyState.bankMatches, [])
        XCTAssertNil(legacyState.lastBankImportAt)
    }
}
