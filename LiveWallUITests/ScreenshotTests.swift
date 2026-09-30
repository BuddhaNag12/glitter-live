import XCTest

/// Captures every main screen on a device for visual review, in light and dark appearance.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreens() {
        continueAfterFailure = true
        for appearance in ["dark", "light"] {
            captureOnboarding(appearance)
            capture("explore", appearance, arguments: ["-tab", "explore"])
            capture("create", appearance, arguments: ["-tab", "create"])
            capture("library", appearance, arguments: ["-tab", "library"])
            captureLibrary(appearance)
            capture("convert-empty", appearance, arguments: ["-tab", "convert"])
            capture("trim-studio", appearance, arguments: ["-tab", "convert", "-demoVideo"], scrolls: 2, settle: 6)
            capture("result", appearance, arguments: ["-tab", "convert", "-demoResult"], settle: 12)
        }
    }

    @MainActor
    private func launch(_ appearance: String, _ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-appearance", appearance]
        app.launch()
        return app
    }

    @MainActor
    private func captureOnboarding(_ appearance: String) {
        let app = launch(appearance, ["-hasCompletedOnboarding", "NO"])
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        for page in 1...3 {
            Thread.sleep(forTimeInterval: 2)
            attach(app, name: "onboarding-\(page)-\(appearance)")
            if page < 3 { app.buttons["Continue"].tap() }
        }
        XCTAssertTrue(app.buttons["Start Creating"].exists)
        app.terminate()
    }

    @MainActor
    private func capture(_ name: String, _ appearance: String, arguments: [String], scrolls: Int = 0, settle: TimeInterval = 2) {
        let app = launch(appearance, arguments + ["-hasCompletedOnboarding", "YES"])
        Thread.sleep(forTimeInterval: settle)
        attach(app, name: "\(name)-\(appearance)")
        for index in 0..<scrolls {
            scrollDown(app)
            attach(app, name: "\(name)-\(index + 2)-\(appearance)")
        }
        app.terminate()
    }

    @MainActor
    private func captureLibrary(_ appearance: String) {
        let app = launch(appearance, ["-tab", "library", "-demoLibrary", "-hasCompletedOnboarding", "YES"])
        let card = app.buttons["creation-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "library-grid-\(appearance)")
        card.tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "library-detail-\(appearance)")
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
