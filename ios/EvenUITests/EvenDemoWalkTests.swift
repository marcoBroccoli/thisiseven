import XCTest

/// Deliberate, slow walk through the polished app for VIDEO capture. Record the
/// sim display with `simctl io <udid> recordVideo` while this runs; the sign-in
/// prefix gets trimmed, and each beat lingers long enough to cut cleanly.
/// Beats: Today (weighted beam) → Inbox (drafts → approve → stamp) → Calendar surface.
final class EvenDemoWalkTests: XCTestCase {
    func testDemoWalk() {
        addUIInterruptionMonitor(withDescription: "password save") { alert in
            for label in ["Not Now", "Never for This Website", "Cancel"]
                where alert.buttons[label].exists
            {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()

        // Sign in as the capture household (trimmed out of the final footage).
        app.buttons["dev-email-signin"].tap()
        let email = app.textFields["auth-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8)); email.tap(); email.typeText("capture-umur@even.dev")
        let pw = app.secureTextFields["auth-password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 8)); pw.tap(); pw.typeText("capture-pass1")
        app.buttons["auth-signin"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if sb.buttons["Not Now"].waitForExistence(timeout: 3) { sb.buttons["Not Now"].tap() }

        // ── BEAT A: Today — the weighted beam settling as pebbles land ──
        go(app, "Today"); sleep(6)

        // ── BEAT B: Inbox — Approval Inbox, then approve one draft ──
        go(app, "Inbox"); sleep(3)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'draft-card-'")).firstMatch
        if card.waitForExistence(timeout: 4) {
            forceTap(card); sleep(2)
            let approve = app.buttons["draft-approve"]
            if approve.waitForExistence(timeout: 4) { forceTap(approve); sleep(3) }
        } else if app.staticTexts["Approval Inbox"].waitForExistence(timeout: 4) {
            // Empty inbox is fine for capture — linger on the empty state.
            sleep(2)
        }
        sleep(1)

        // ── BEAT C: Shared calendar surface (from Inbox chrome chip) ──
        let calendarChip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "SHARED")
        ).firstMatch
        if calendarChip.waitForExistence(timeout: 4) {
            forceTap(calendarChip); sleep(5)
        }
        sleep(1)
    }

    private func go(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "missing tab \(name)")
        forceTap(tab)
    }

    private func forceTap(_ element: XCUIElement) {
        if element.isHittable { element.tap() }
        else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }
}
