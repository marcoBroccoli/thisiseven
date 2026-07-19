import XCTest

/// Walks the staged capture household and attaches screenshots of every tab
/// in light and dark mode. Not a correctness test — an evidence generator.
/// Stage data first: scratchpad/stage-capture.sh (capture-umur@even.dev).
final class EvenCaptureTests: XCTestCase {

    func testCaptureScreens() throws {
        // iOS offers to save the typed password; swat the sheet away.
        addUIInterruptionMonitor(withDescription: "password save") { alert in
            for label in ["Not Now", "Never for This Website", "Cancel"]
            where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()

        // Sign in as the capture account.
        app.buttons["dev-email-signin"].tap()
        let email = app.textFields["auth-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8))
        email.tap()
        email.typeText("capture-umur@even.dev")
        let password = app.textFields["auth-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 8))
        password.tap()
        password.typeText("capture-pass1")
        app.buttons["Sign in"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        // Trigger the interruption monitor (it only fires on interaction),
        // and dismiss the save-password sheet directly if it is visible.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 3) {
            springboard.buttons["Not Now"].tap()
        }
        go(app, "Today")
        sleep(1)

        snap(app, "01-today-light")
        go(app, "Inbox"); snap(app, "02-inbox-light")
        go(app, "Money"); snap(app, "03-money-light")
        go(app, "Reset"); snap(app, "04-reset-light")

        // Reset step 1 + 3 (computed bars, trades)
        if app.buttons["Start the reset"].waitForExistence(timeout: 5) {
            forceTap(app.buttons["Start the reset"])
            sleep(1)
            snap(app, "05-reset-week-honestly")
            if app.buttons["Next — say one kind thing"].exists {
                forceTap(app.buttons["Next — say one kind thing"])
                sleep(1)
                snap(app, "06-reset-kind-thing")
            }
        }

        // Dark mode
        go(app, "Today")
        toggleDark(app)
        sleep(1)
        snap(app, "07-today-dark")
        go(app, "Inbox"); snap(app, "08-inbox-dark")
        go(app, "Money"); snap(app, "09-money-dark")
        toggleDark(app)   // leave the app in light mode
    }

    private func forceTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func go(_ app: XCUIApplication, _ tab: String) {
        app.tabBars.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", tab)).firstMatch.tap()
        sleep(1)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Evidence generator for the stepwise-tilt physics: signs in, then
/// relaunches with --physics-stress N at several counts × both palettes.
final class EvenStressCaptureTests: XCTestCase {
    func testCaptureTiltSteps() throws {
        var app = XCUIApplication()
        app.launchArguments = ["--skip-google-prompt"]
        app.launch()

        // Sign in if the welcome screen is up (session may be cleared).
        if app.buttons["dev-email-signin"].waitForExistence(timeout: 6) {
            app.buttons["dev-email-signin"].tap()
            let email = app.textFields["auth-email"]
            XCTAssertTrue(email.waitForExistence(timeout: 8))
            email.tap()
            email.typeText("capture-umur@even.dev")
            let password = app.textFields["auth-password"].exists
                ? app.textFields["auth-password"] : app.secureTextFields.firstMatch
            password.tap()
            password.typeText("capture-pass1")
            app.buttons["Sign in"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 20))

        for dark in [false, true] {
            for count in [1, 3, 16] {
                app.terminate()
                app = XCUIApplication()
                app.launchArguments = ["--skip-google-prompt", "--physics-stress", "\(count)"]
                app.launch()
                XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 15))
                if dark != isDarkNow(app) {
                    toggleDark(app)
                }
                sleep(6)   // let balls drop and the beam settle
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "tilt-\(count)-\(dark ? "dark" : "light")"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
    }

    private func isDarkNow(_ app: XCUIApplication) -> Bool {
        // The profile sheet's toggle shows "sun.max" (label Sun) in dark mode;
        // callers must have the sheet open when they care. We instead track
        // the last state we set — captures always start from light.
        Self.darkNow
    }
    static var darkNow = false
}


/// Profile-sheet evidence: light + dark.
final class EvenProfileCaptureTests: XCTestCase {
    func testCaptureTodayCollapse() throws {
        var app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()
        // The capture household has enough rows to actually scroll.
        if app.buttons["dev-email-signin"].waitForExistence(timeout: 6) {
            app.buttons["dev-email-signin"].tap()
            let email = app.textFields["auth-email"]
            XCTAssertTrue(email.waitForExistence(timeout: 8))
            email.tap()
            email.typeText("capture-umur@even.dev")
            let password = app.textFields["auth-password"].exists
                ? app.textFields["auth-password"] : app.secureTextFields.firstMatch
            password.tap()
            password.typeText("capture-pass1")
            app.buttons["Sign in"].tap()
        }
        XCTAssertTrue(app.buttons["profile-button"].waitForExistence(timeout: 20))
        sleep(3)
        let atRest = XCTAttachment(screenshot: app.screenshot())
        atRest.name = "today-large-rest"
        atRest.lifetime = .keepAlways
        add(atRest)
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "today-collapsed"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        app.swipeDown()
    }

    func testCaptureProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-google-prompt"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-button"].waitForExistence(timeout: 20))
        for name in ["profile-light", "profile-dark"] {
            for _ in 0..<4 where !app.buttons["dark-toggle"].exists {
                app.buttons["profile-button"].tap()
                if app.buttons["dark-toggle"].waitForExistence(timeout: 3) { break }
            }
            sleep(1)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
            if name == "profile-light" {
                app.buttons["dark-toggle"].tap()
                sleep(1)
            } else {
                app.buttons["dark-toggle"].tap()   // back to light
                if app.buttons["sheet-close"].waitForExistence(timeout: 3) {
                    app.buttons["sheet-close"].tap()
                }
            }
        }
    }
}

extension XCTestCase {
    /// Dark toggle moved into the profile sheet (toolbar avatar chip).
    func toggleDark(_ app: XCUIApplication) {
        let toggle = app.buttons["dark-toggle"]
        for _ in 0..<4 where !toggle.exists {
            app.buttons["profile-button"].tap()
            if toggle.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        toggle.tap()
        if app.buttons["sheet-close"].waitForExistence(timeout: 4) {
            app.buttons["sheet-close"].tap()
        } else {
            app.swipeDown()
        }
    }
}
