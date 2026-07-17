import XCTest

/// End-to-end MVP verification against the live evend stack (localhost:8091).
/// Two real accounts pair into one household; no seeded data anywhere.
/// Mirrors the PRD "definition of done".
final class EvenE2ETests: XCTestCase {

    let pass = "evene2e-pass1"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFullMVPFlow() throws {
        // No hyphens: the sim keyboard's smart punctuation turns "-" into an
        // en dash, which GoTrue rejects as an invalid email.
        let stamp = String(Int(Date().timeIntervalSince1970))
        let emailA = "umur\(stamp)@even.dev"
        let emailB = "beste\(stamp)@even.dev"

        // ── Account A: sign up, found the household ──────────────────────
        var app = launchFresh()
        signUp(app, email: emailA)

        tapExpecting(app.buttons["Start our household"],
                     reveals: app.textFields["household-name"])
        typeInto(app.textFields["household-name"], "Prinsengracht 12", app: app)
        typeInto(app.textFields["display-name-create"], "Umur", app: app)
        let invite = app.staticTexts["invite-code-label"]
        tapExpecting(app.buttons["Create — get the invite code"], reveals: invite)
        let code = String(invite.label.suffix(6))
        XCTAssertEqual(code.count, 6)

        // ── A: two chores, toggle one → beam reads 100 ───────────────────
        addTask(app, title: "Dishes tonight")
        addTask(app, title: "Water the plants")
        tap(app.buttons["check-Dishes tonight"])
        XCTAssertTrue(app.staticTexts["100"].waitForExistence(timeout: 10),
                      "solo completion should read 100%")

        // ── A: propose a draft, approve it into THE ADMIN ────────────────
        tap(tab(app, "Inbox"))
        tapExpecting(app.buttons["fab-propose"], reveals: app.textFields["draft-from"])
        typeInto(app.textFields["draft-from"], "Vattenfall", app: app)
        typeInto(app.textFields["draft-subject"], "July energy bill", app: app)
        tapExpecting(app.buttons["Send to the inbox"],
                     reveals: app.buttons["draft-card-July energy bill"])
        tapExpecting(app.buttons["draft-card-July energy bill"],
                     reveals: app.buttons["draft-approve"])
        tap(app.buttons["draft-approve"])
        XCTAssertTrue(app.staticTexts["ON THE CALENDAR ✓"].waitForExistence(timeout: 10))
        tap(tab(app, "Today"))
        XCTAssertTrue(app.staticTexts["July energy bill"].waitForExistence(timeout: 10),
                      "approved draft becomes admin work")

        // ── A: front an expense ──────────────────────────────────────────
        tap(tab(app, "Money"))
        tapExpecting(app.buttons["fab-add-expense"], reveals: app.textFields["expense-title"])
        typeInto(app.textFields["expense-title"], "Weekly groceries", app: app)
        typeInto(app.textFields["expense-amount"], "86.20", app: app)
        tapExpecting(app.buttons["Add receipt"], reveals: app.staticTexts["€86.20"])

        // ── Account B: join with the invite code ─────────────────────────
        app.terminate()
        app = launchFresh()
        signUp(app, email: emailB)

        tapExpecting(app.buttons["I have an invite code"],
                     reveals: app.textFields["invite-code"])
        typeInto(app.textFields["invite-code"], code, app: app)
        typeInto(app.textFields["display-name-join"], "Beste", app: app)
        // Shared state visible to B: A's open task appears after joining.
        tapExpecting(app.buttons["Join the household"],
                     reveals: app.staticTexts["Water the plants"])
        tap(tab(app, "Money"))
        XCTAssertTrue(app.staticTexts["€43.10"].waitForExistence(timeout: 10),
                      "B owes half of A's groceries")
        tapExpecting(app.buttons["Settle up"], reveals: app.buttons["Settled ✓"])
        XCTAssertTrue(app.staticTexts["€0.00"].waitForExistence(timeout: 10))

        // ── B: run the Sunday reset and pour the pans ────────────────────
        tap(tab(app, "Reset"))
        tapExpecting(app.buttons["Start the reset"],
                     reveals: app.buttons["Next — say one kind thing"])
        tap(app.buttons["Next — say one kind thing"])
        tap(app.buttons["Next — trade for next week"])
        tapExpecting(app.buttons["Close the week — pour the pans"],
                     reveals: app.staticTexts["Week 1, poured out."],
                     revealTimeout: 6)
        XCTAssertTrue(app.staticTexts["Week 1, poured out."].waitForExistence(timeout: 12))

        // ── Back as A: partner present, pans empty, level again ──────────
        app.terminate()
        app = launchFresh()
        signIn(app, email: emailA)
        XCTAssertTrue(app.staticTexts["BESTE"].waitForExistence(timeout: 12),
                      "A sees Beste on the scale")
        XCTAssertTrue(app.staticTexts["Empty pans. A new week, level by definition."]
            .waitForExistence(timeout: 10), "closed week starts level")
    }

    // MARK: - Helpers

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()
        return app
    }

    private func signUp(_ app: XCUIApplication, email: String) {
        tap(app.buttons["dev-email-signin"])
        typeInto(app.textFields["auth-email"], email, app: app)
        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 8))
        password.tap()
        password.typeText(pass)
        tapExpecting(app.buttons["Sign up"], reveals: app.buttons["Start our household"],
                     attempts: 3, revealTimeout: 6)
    }

    private func signIn(_ app: XCUIApplication, email: String) {
        tap(app.buttons["dev-email-signin"])
        typeInto(app.textFields["auth-email"], email, app: app)
        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 8))
        password.tap()
        password.typeText(pass)
        tap(app.buttons["Sign in"])
    }

    private func addTask(_ app: XCUIApplication, title: String) {
        tapExpecting(app.buttons["fab-add-task"], reveals: app.textFields["task-title"])
        typeInto(app.textFields["task-title"], title, app: app)
        tapExpecting(app.buttons["Add to the week"], reveals: app.staticTexts[title])
    }

    private func typeInto(_ field: XCUIElement, _ text: String, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 8), "field for '\(text)'")
        field.tap()
        field.typeText(text)
        // Dismissing focus keeps later taps from hitting the keyboard.
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
    }

    /// Native tab-bar button; the Inbox label may carry a badge value.
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.tabBars.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing: \(element)")
        // Sheets dismissing over an element leave it briefly unhittable.
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        forceTap(element)
    }

    /// Elements that are visible but report unhittable (contextMenu wrappers,
    /// mid-dismiss sheets) get a coordinate tap instead.
    private func forceTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Taps that must reveal a new surface can silently miss during sheet
    /// transitions — retry until the revealed element exists.
    private func tapExpecting(_ button: XCUIElement, reveals: XCUIElement,
                              attempts: Int = 4, revealTimeout: TimeInterval = 3) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing: \(button)")
        for _ in 0..<attempts {
            if !button.exists { break }   // tap landed; surface may be mid-transition
            forceTap(button)
            if reveals.waitForExistence(timeout: revealTimeout) { return }
        }
        XCTAssertTrue(reveals.waitForExistence(timeout: 8),
                      "tapping \(button) never revealed \(reveals)")
    }
}
