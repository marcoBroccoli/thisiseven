import XCTest

/// Evidence generator for the Inbox UI pass (opaque surface switcher, swipe
/// approve / dismiss, review-sheet reminder provenance, month calendar).
/// Not a correctness test — it attaches screenshots of each changed surface.
///
/// Needs a seeded household on the live stack; pass the account in via
/// `INBOX_CAPTURE_EMAIL` / `INBOX_CAPTURE_PASSWORD` (see the seeding curl calls
/// in the task notes). Skips itself when they are absent.
final class EvenInboxCaptureTests: XCTestCase {
    private var email: String { ProcessInfo.processInfo.environment["INBOX_CAPTURE_EMAIL"] ?? "" }
    private var password: String { ProcessInfo.processInfo.environment["INBOX_CAPTURE_PASSWORD"] ?? "" }

    func testCaptureInboxSurfaces() throws {
        try XCTSkipIf(email.isEmpty, "INBOX_CAPTURE_EMAIL not set")

        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()

        signIn(app)
        let inbox = app.tabBars.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Inbox")
        ).firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 20), "signed in and on the tab bar")
        // The floating tab bar swallows the first tap while Today is still
        // settling — keep tapping until the Inbox header lands.
        var landed = false
        for _ in 0 ..< 6 where !landed {
            inbox.tap()
            landed = app.staticTexts["Approval Inbox"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(landed, "Inbox surface never appeared")
        sleep(2)
        snap(app, "01-inbox-list")

        // Scroll content under the pinned switcher — this is the ghosting test.
        app.swipeUp()
        sleep(1)
        snap(app, "02-inbox-scrolled-under-switcher")

        // Partial drags so a tray stays open instead of firing a full swipe.
        let bill = card(app, "Water bill — €84.30, due 14 August")
        XCTAssertTrue(bill.waitForExistence(timeout: 8), "seeded draft row")
        drag(bill, from: 0.1, to: 0.9)
        sleep(1)
        snap(app, "03-swipe-approve-revealed")
        drag(bill, from: 0.9, to: 0.1) // close it again
        sleep(1)

        let dentist = card(app, "Cleaning appointment Thursday 11:20")
        XCTAssertTrue(dentist.waitForExistence(timeout: 8))
        drag(dentist, from: 1.0, to: 0.1)
        sleep(1)
        snap(app, "04-swipe-dismiss-revealed")
        drag(dentist, from: 0.1, to: 1.0)
        sleep(1)

        // End-to-end: the leading tray's Approve really approves.
        drag(bill, from: 0.1, to: 0.9)
        let approve = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()
        sleep(3)
        snap(app, "05-after-swipe-approve")
        XCTAssertFalse(
            card(app, "Water bill — €84.30, due 14 August").waitForExistence(timeout: 8),
            "approved draft leaves the list"
        )

        // Review sheet — detected date.
        openDraft(app, subject: "Health insurance renewal — decide before 20 August")
        sleep(1)
        snap(app, "06-review-detected-date")
        closeSheet(app)

        // Review sheet — nothing detected (the Vattenfall draft has no due_on).
        openDraft(app, subject: "Your new energy contract is ready to sign")
        sleep(1)
        snap(app, "07-review-no-date-detected")
        closeSheet(app)

        // Calendar surface — month grid, then the agenda layout.
        let switcher = app.segmentedControls["inbox-surface-switch"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 8))
        switcher.buttons.element(boundBy: 1).tap()
        sleep(3)
        snap(app, "08-calendar-month-grid")

        let day = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Day 14")
        ).firstMatch
        if day.waitForExistence(timeout: 5) {
            day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(1)
            snap(app, "09-calendar-day-filtered")
        }

        app.buttons["LIST"].firstMatch.tap()
        sleep(1)
        snap(app, "10-calendar-agenda-layout")
    }

    // MARK: - Helpers

    /// Normalized offsets are relative to the (collapsed) a11y frame, so the
    /// span is generous on purpose — enough travel to open a tray.
    private func drag(_ element: XCUIElement, from: CGFloat, to: CGFloat) {
        element.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: element.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
            )
    }

    /// Rows combine their children into one a11y element — target the card id.
    private func card(_ app: XCUIApplication, _ subject: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "draft-card-\(subject)")
            .firstMatch
    }

    private func openDraft(_ app: XCUIApplication, subject: String) {
        let element = card(app, subject)
        if !element.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 8), "draft '\(subject)'")
        // The combined element reports the label's frame, not the card's — a
        // normalized coordinate still lands inside the row.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = app.staticTexts["Review draft"].waitForExistence(timeout: 8)
    }

    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) {
            close.tap()
        }
        sleep(1)
    }

    private func signIn(_ app: XCUIApplication) {
        let dev = app.buttons["dev-email-signin"]
        XCTAssertTrue(dev.waitForExistence(timeout: 20))
        dev.tap()
        let field = app.textFields["auth-email"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(email)
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        let secure = app.secureTextFields["auth-password"]
        XCTAssertTrue(secure.waitForExistence(timeout: 8))
        secure.tap()
        secure.typeText(password)
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        app.buttons["auth-signin"].tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 5) {
            springboard.buttons["Not Now"].tap()
        }
        let skip = app.buttons["SKIP"]
        if skip.waitForExistence(timeout: 6) {
            skip.tap()
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
