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
        let password = app.secureTextFields.firstMatch
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
        app.buttons["tab-today"].tap()
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
        app.buttons["dark-toggle"].tap()
        sleep(1)
        snap(app, "07-today-dark")
        go(app, "Inbox"); snap(app, "08-inbox-dark")
        go(app, "Money"); snap(app, "09-money-dark")
        app.buttons["dark-toggle"].tap()   // leave the app in light mode
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
