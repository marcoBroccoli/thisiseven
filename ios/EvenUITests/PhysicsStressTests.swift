import XCTest

/// Containment stress: 16 max-size balls at full tilt must stay in the
/// bucket. Screenshots are the evidence; run with -only-testing.
final class PhysicsStressTests: XCTestCase {

    func testBucketContainment() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt", "--physics-stress"]
        app.launch()

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

        XCTAssertTrue(app.buttons["profile-button"].waitForExistence(timeout: 15))
        sleep(7)   // let the pile drop and fully settle
        snap(app, "90-stress-light")

        toggleDark(app)
        sleep(2)
        snap(app, "91-stress-dark")
        toggleDark(app)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
