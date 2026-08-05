import XCTest

/// End-to-end MVP verification against the live evend stack (localhost:8091).
/// Two real accounts pair into one household; no seeded data anywhere.
/// Targets the TCA Feature chrome: Onboarding → HouseholdSetup → Today + Inbox.
final class EvenE2ETests: XCTestCase {
    let pass = "evene2e-pass1"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSharedTodoFlow() {
        // No hyphens: the sim keyboard's smart punctuation turns "-" into an
        // en dash, which GoTrue rejects as an invalid email.
        let stamp = String(Int(Date().timeIntervalSince1970))
        let emailA = "umur\(stamp)@even.dev"
        let emailB = "beste\(stamp)@even.dev"

        // ── Account A: sign up, found the household ──────────────────────
        var app = launchFresh()
        signUp(app, email: emailA)
        finishHowItWorks(app)

        tapExpecting(app.buttons["Start our household"],
                     reveals: app.textFields["household-name"])
        typeInto(app.textFields["household-name"], "Prinsengracht 12", app: app)
        typeInto(app.textFields["display-name-create"], "Umur", app: app)
        let invite = app.staticTexts["invite-code-label"]
        tapExpecting(app.buttons["create-household"], reveals: invite)
        let code = String(invite.label.suffix(6))
        XCTAssertEqual(code.count, 6)
        tap(app.buttons["invite-continue"])

        // ── A: capture household todos and complete one ──────────────────
        XCTAssertTrue(tab(app, "Today").waitForExistence(timeout: 12))
        addTask(app, title: "Dishes tonight")
        addTask(app, title: "Water the plants")
        tap(app.buttons["check-Dishes tonight"])
        XCTAssertTrue(app.staticTexts["Water the plants"].waitForExistence(timeout: 10))
        tap(tab(app, "Inbox"))
        XCTAssertTrue(app.staticTexts["Approval Inbox"].waitForExistence(timeout: 10))

        // ── Account B: join with the invite code ─────────────────────────
        app.terminate()
        app = launchFresh()
        signUp(app, email: emailB)
        finishHowItWorks(app)

        tapExpecting(app.buttons["mode-join"],
                     reveals: app.textFields["invite-code"])
        typeInto(app.textFields["invite-code"], code, app: app)
        typeInto(app.textFields["display-name-join"], "Beste", app: app)
        tapExpecting(app.buttons["join-household"],
                     reveals: app.staticTexts["Water the plants"])
        XCTAssertTrue(app.staticTexts["Dishes tonight"].waitForExistence(timeout: 10),
                      "B sees the household's completed todo")

        // ── Back as A: both members see the same unified list ────────────
        app.terminate()
        app = launchFresh()
        signIn(app, email: emailA)
        XCTAssertTrue(app.staticTexts["Water the plants"].waitForExistence(timeout: 12),
                      "A sees the household's shared todo")
    }

    // MARK: - Helpers

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()
        return app
    }

    private func finishHowItWorks(_ app: XCUIApplication) {
        let skip = app.buttons["SKIP"]
        if skip.waitForExistence(timeout: 8) {
            tap(skip)
        }
    }

    private func signUp(_ app: XCUIApplication, email: String) {
        tap(app.buttons["dev-email-signin"])
        typeInto(app.textFields["auth-email"], email, app: app)
        let password = app.secureTextFields["auth-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 8))
        password.tap()
        password.typeText(pass)
        tapExpecting(app.buttons["auth-signup"], reveals: app.buttons["SKIP"],
                     attempts: 3, revealTimeout: 8)
        dismissSavePassword()
    }

    private func dismissSavePassword() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 3) {
            springboard.buttons["Not Now"].tap()
        }
    }

    private func signIn(_ app: XCUIApplication, email: String) {
        tap(app.buttons["dev-email-signin"])
        typeInto(app.textFields["auth-email"], email, app: app)
        let password = app.secureTextFields["auth-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 8))
        password.tap()
        password.typeText(pass)
        tap(app.buttons["auth-signin"])
        dismissSavePassword()
    }

    private func addTask(_ app: XCUIApplication, title: String) {
        tapExpecting(app.buttons["fab-add-task"], reveals: app.textFields["task-title"])
        typeInto(app.textFields["task-title"], title, app: app)
        tapExpecting(app.buttons["task-save"], reveals: app.staticTexts[title])
    }

    private func typeInto(_ field: XCUIElement, _ text: String, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 8), "field for '\(text)'")
        field.tap()
        // Clear any prefilled value (dev email sheet).
        if let value = field.value as? String, !value.isEmpty {
            let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            field.typeText(clear)
        }
        field.typeText(text)
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
    }

    /// Native tab-bar button; the Inbox label may carry a badge value.
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.tabBars.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing: \(element)")
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        forceTap(element)
    }

    private func forceTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func tapExpecting(_ button: XCUIElement, reveals: XCUIElement,
                              attempts: Int = 4, revealTimeout: TimeInterval = 4)
    {
        for _ in 0 ..< attempts {
            if reveals.waitForExistence(timeout: 0.5) { return }
            if button.waitForExistence(timeout: 2) {
                forceTap(button)
            }
            if reveals.waitForExistence(timeout: revealTimeout) { return }
        }
        XCTFail("never revealed \(reveals) after tapping \(button)")
    }
}
