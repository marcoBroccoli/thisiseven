import EvenCore
import XCTest

/// `X-Household-Id` is sent only once the client has actually picked a place —
/// silence is what keeps build 12 and fresh installs behaving as before.
final class ActiveHouseholdTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ActiveHousehold.storageKey)
        super.tearDown()
    }

    func testUnsetReadsAsNothingToSend() {
        UserDefaults.standard.removeObject(forKey: ActiveHousehold.storageKey)
        XCTAssertNil(ActiveHousehold.id)

        // `@Shared(.appStorage:)` clears by writing an empty string, not by
        // removing the key.
        UserDefaults.standard.set("", forKey: ActiveHousehold.storageKey)
        XCTAssertNil(ActiveHousehold.id)

        UserDefaults.standard.set("not-a-uuid", forKey: ActiveHousehold.storageKey)
        XCTAssertNil(ActiveHousehold.id)
    }

    /// Postgres uuid compares are case-sensitive strings on the wire — the id
    /// always goes out lowercased, whatever case it was written in.
    func testTheIdIsAlwaysLowercased() {
        let id = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        ActiveHousehold.set(id)
        XCTAssertEqual(ActiveHousehold.id, "cccccccc-cccc-cccc-cccc-cccccccccccc")

        ActiveHousehold.clear()
        XCTAssertNil(ActiveHousehold.id)
    }
}
