import XCTest
import AppKit

final class TuckUITests: XCTestCase {
    @MainActor
    func testLaunchShowsMCPSetupAndNoStandaloneSecretField() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["connectButton"].waitForExistence(timeout: 10))
        // Legacy scroll bars must never sit over the artwork, even with a mouse attached.
        XCTAssertEqual(app.windows.firstMatch.scrollBars.count, 0, "no visible scroll bar at rest")
        app.buttons["connectButton"].click()
        XCTAssertTrue(app.buttons["copySetupButton"].exists)
        app.buttons["copySetupButton"].click()
        let pasteboard = NSPasteboard.general
        let generation = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == generation { pasteboard.clearContents() }
        }
        let instructions = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(instructions.contains("--mcp"))
        XCTAssertTrue(instructions.contains("name: tuck"))
        XCTAssertTrue(instructions.contains("save_credential"))
        XCTAssertFalse(app.staticTexts["setupError"].exists)
        XCTAssertFalse(app.secureTextFields["secretField"].exists)
        XCTAssertFalse(app.textFields["serviceField"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Tuck connection screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension TuckUITests {
    /// App Review (Guideline 4, 2026-09-11): closing the main window left no menu item to reopen it.
    @MainActor
    func testClosedMainWindowReopensFromWindowMenu() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["connectButton"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 5))
        app.activate()
        let windowMenu = app.menuBars.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 5), "Window menu must exist so a closed main window can be reopened")
        windowMenu.click()
        let reopen = app.menuItems["Show Tuck"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        XCTAssertTrue(reopen.isEnabled)
        reopen.click()
        XCTAssertTrue(app.buttons["connectButton"].waitForExistence(timeout: 10), "Show Tuck must reopen the main window")
    }
}
