import XCTest

/// Captures every main screen on a device for visual review, in light and dark appearance.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreens() {
        continueAfterFailure = true
        for appearance in ["dark", "light"] {
            captureOnboarding(appearance)
            captureExplore(appearance)
            capture("library", appearance, arguments: ["-tab", "library"])
            captureLibrary(appearance)
            capture("convert-empty", appearance, arguments: ["-tab", "convert"])
            capture("trim-studio", appearance, arguments: ["-tab", "convert", "-demoVideo"], scrolls: 2) { app in
                // Save is enabled once the demo video has loaded.
                app.buttons["Save"].firstMatch
            }
            capture("result", appearance, arguments: ["-tab", "convert", "-demoResult"]) { app in
                app.buttons["Set as Wallpaper"]
            }
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
    private func capture(
        _ name: String, _ appearance: String, arguments: [String], scrolls: Int = 0,
        readyWhen ready: ((XCUIApplication) -> XCUIElement)? = nil
    ) {
        let app = launch(appearance, arguments + ["-hasCompletedOnboarding", "YES"])
        if let ready {
            XCTAssertTrue(waitUntilEnabled(ready(app)), "\(name) never became ready")
        }
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "\(name)-\(appearance)")
        for index in 0..<scrolls {
            scrollDown(app)
            attach(app, name: "\(name)-\(index + 2)-\(appearance)")
        }
        app.terminate()
    }

    @MainActor
    private func captureExplore(_ appearance: String) {
        let app = launch(appearance, ["-tab", "explore", "-hasCompletedOnboarding", "YES"])
        let card = app.buttons["catalog-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Catalog didn't load")
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "explore-\(appearance)")
        card.tap()
        Thread.sleep(forTimeInterval: 4)
        attach(app, name: "explore-detail-\(appearance)")
        app.terminate()
    }

    @MainActor
    private func captureLibrary(_ appearance: String) {
        let app = launch(appearance, ["-tab", "library", "-demoLibrary", "-hasCompletedOnboarding", "YES"])
        // Seeding encodes three Live Photos, which takes a while on a simulator.
        XCTAssertTrue(app.buttons.matching(identifier: "creation-card").element(boundBy: 2).waitForExistence(timeout: 120))
        let card = app.buttons["creation-card"].firstMatch
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "library-grid-\(appearance)")
        card.tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "library-detail-\(appearance)")
        app.terminate()
    }

    /// Waits on the element rather than a fixed delay, since demo videos render at different speeds on each machine.
    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 120) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
