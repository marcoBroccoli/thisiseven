import XCTest

/// Evidence generator for the Sunday ritual ("the pour").
/// Requires the dev household `pour-dev@even.test` with an overdue open week.
/// Not a correctness test — it walks the five beats and writes PNGs.
final class EvenResetCaptureTests: XCTestCase {
    private let outputDirectory =
        ProcessInfo.processInfo.environment["RESET_CAPTURE_DIR"] ?? NSTemporaryDirectory()

    func testCaptureTheRitual() {
        addUIInterruptionMonitor(withDescription: "password save") { alert in
            for label in ["Not Now", "Never for This Website", "Cancel"]
                where alert.buttons[label].exists
            {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--skip-google-prompt"]
        app.launch()

        XCTAssertTrue(app.buttons["dev-email-signin"].waitForExistence(timeout: 20))
        app.buttons["dev-email-signin"].tap()
        let email = app.textFields["auth-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        // The dev sheet prefills Umur's address — clear it before typing.
        if let existing = email.value as? String, !existing.isEmpty {
            email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
        }
        email.typeText("pour-dev@even.test")
        let password = app.secureTextFields["auth-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap()
        if let existing = password.value as? String, !existing.isEmpty {
            password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
        }
        password.typeText("pourritual123")
        app.buttons["auth-signin"].tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 6) {
            springboard.buttons["Not Now"].tap()
        }

        sleep(4)

        // Beat 1 — the cover. The ritual presents itself: the week is overdue.
        let advance = app.buttons["reset-continue"]
        XCTAssertTrue(advance.waitForExistence(timeout: 25), "the ritual never presented")
        sleep(3) // let the beam settle to its final tilt
        snap(app, "ritual-01")

        // Beat 2 — the split.
        advance.tap()
        sleep(3) // the three rows draw in one at a time
        snap(app, "ritual-02")

        // Beat 3 — the biggest carry.
        app.buttons["reset-continue"].tap()
        sleep(2)
        snap(app, "ritual-03")

        // Beat 4 — one kind thing. Veiled first, then written, then revealed.
        app.buttons["reset-continue"].tap()
        sleep(2)
        snap(app, "ritual-04a")

        let field = app.textViews["reset-appreciation-field"]
        if field.waitForExistence(timeout: 6) {
            field.tap()
            field.typeText("You never once made the kitchen a negotiation. Thank you.")
            if app.buttons["reset-save-appreciation"].exists {
                app.buttons["reset-save-appreciation"].tap()
            }
            sleep(3)
        }
        snap(app, "ritual-04")

        // Beat 5 — the pour, waiting on the hold.
        if app.buttons["reset-continue"].exists {
            app.buttons["reset-continue"].tap()
        }
        sleep(3)
        snap(app, "ritual-05")

        // The hold itself.
        let hold = app.descendants(matching: .any)["reset-hold-to-pour"].firstMatch
        XCTAssertTrue(hold.waitForExistence(timeout: 8), "hold control missing")
        hold.press(forDuration: 2.2)
        sleep(4) // pebbles leave, the beam comes back to level
        snap(app, "ritual-06")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            print("RESET-CAPTURE could not write \(url.path): \(error)")
        }
    }
}
