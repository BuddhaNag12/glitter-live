import XCTest

/// Captures every main screen on a device for visual review.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreens() {
        continueAfterFailure = true
        captureOnboarding()
        capture("explore", arguments: ["-tab", "explore"])
        capture("create", arguments: ["-tab", "create"])
        capture("library", arguments: ["-tab", "library"])
        captureLibrary()
        capture("convert-empty", arguments: ["-tab", "convert"])
        capture("trim-studio", arguments: ["-tab", "convert", "-demoVideo"], scrolls: 2, settle: 6)
        capture("result", arguments: ["-tab", "convert", "-demoResult"], settle: 12)
    }

    @MainActor
    private func captureOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
        app.launch()
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        for page in 1...3 {
            Thread.sleep(forTimeInterval: 2)
            attach(app, name: "onboarding-\(page)")
            scrollDown(app)
            attach(app, name: "onboarding-\(page)-bottom")
            if page < 3 { app.buttons["Continue"].tap() }
        }
        XCTAssertTrue(app.buttons["Start Creating"].exists)
        app.terminate()
    }

    @MainActor
    private func capture(_ name: String, arguments: [String], scrolls: Int = 0, settle: TimeInterval = 2) {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-hasCompletedOnboarding", "YES"]
        app.launch()
        Thread.sleep(forTimeInterval: settle)
        attach(app, name: name)
        for index in 0..<scrolls {
            scrollDown(app)
            attach(app, name: "\(name)-\(index + 2)")
        }
        app.terminate()
    }

    @MainActor
    private func captureLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "library", "-demoLibrary", "-hasCompletedOnboarding", "YES"]
        app.launch()
        let card = app.buttons["creation-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "library-grid")
        card.tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "library-detail")
        app.terminate()
    }

    /// Drags near the left edge, away from the timeline and preview controls.
    @MainActor
    private func scrollDown(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.3)))
        Thread.sleep(forTimeInterval: 1)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
