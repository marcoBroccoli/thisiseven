import XCTest

/// Deliberate, slow walk through the polished app for VIDEO capture. Record the
/// sim display with `simctl io <udid> recordVideo` while this runs; the sign-in
/// prefix gets trimmed, and each beat lingers long enough to cut cleanly.
/// Beats: Today (weighted beam settling) → Inbox (categorized drafts → approve →
/// ink stamp) → Calendar (month + dots + agenda) → Money (Settle up → €0.00).
final class EvenDemoWalkTests: XCTestCase {
    func testDemoWalk() throws {
        addUIInterruptionMonitor(withDescription: "password save") { alert in
            for label in ["Not Now", "Never for This Website", "Cancel"]
            where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()

        // Sign in as the capture household (trimmed out of the final footage).
        app.buttons["dev-email-signin"].tap()
        let email = app.textFields["auth-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8)); email.tap(); email.typeText("capture-umur@even.dev")
        let pw = app.textFields["auth-password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 8)); pw.tap(); pw.typeText("capture-pass1")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if sb.buttons["Not Now"].waitForExistence(timeout: 3) { sb.buttons["Not Now"].tap() }

        // ── BEAT A: Today — the weighted beam settling as pebbles land ──
        go(app, "Today"); sleep(6)

        // ── BEAT B: Inbox — categorized Gmail drafts, then approve one ──
        go(app, "Inbox"); sleep(3)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'draft-card-'")).firstMatch
        if card.waitForExistence(timeout: 4) {
            forceTap(card); sleep(2)
            let approve = app.buttons["draft-approve"]
            if approve.waitForExistence(timeout: 4) { forceTap(approve); sleep(3) } // ink stamp
        }
        sleep(1)

        // ── BEAT C: Calendar — the shared month, day dots, agenda ──
        go(app, "Calendar"); sleep(5)

        // ── BEAT D: Money — settle up, the coin crosses to €0.00 ──
        go(app, "Money"); sleep(2)
        let settle = app.buttons["settle-button"]
        if settle.waitForExistence(timeout: 4) { forceTap(settle); sleep(4) }
        sleep(1)
    }

    private func forceTap(_ el: XCUIElement) {
        if el.isHittable { el.tap() }
        else { el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    private func go(_ app: XCUIApplication, _ tab: String) {
        app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", tab)).firstMatch.tap()
        sleep(1)
    }
}
