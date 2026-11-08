import XCTest

/// iOS 27's Liquid Glass can crash while re-rendering glass (GlassMaterialProvider.Parameters.RingShadow.distanceRange).
/// On a device it showed up after reopening the intro from Settings, skipping it and tapping a tab straight away.
/// These replay that path in many combinations so it can't quietly come back.
final class TabRoundTripTests: XCTestCase {
    private let tabs = ["Explore", "Create", "Convert", "Library"]

    /// Without forcing onboarding as done: a launch argument would override "Show intro again".
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-noPrompts"]
        app.launch()
        let skip = app.buttons["Skip"].firstMatch
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 15))
        // Visit every tab once, as on the device.
        for tab in tabs { app.tabBars.buttons[tab].tap() }
        return app
    }

    /// Opens Settings on `startTab`, reopens the intro, moves `pages` pages in, leaves it (Skip, or Start Creating on
    /// the last page), then taps each of `targets` without waiting. Fails if the app is no longer running.
    @MainActor
    private func replayIntro(_ app: XCUIApplication, from startTab: String, pages: Int, thenTap targets: [String], _ label: String) {
        app.tabBars.buttons[startTab].tap()
        app.buttons["Settings"].firstMatch.tap()
        let showIntro = app.buttons["Show intro again"].firstMatch
        guard showIntro.waitForExistence(timeout: 5) else { return XCTFail("Settings didn't open: \(label)") }
        showIntro.tap()
        guard app.buttons["Skip"].firstMatch.waitForExistence(timeout: 5) else { return XCTFail("The intro didn't open: \(label)") }
        for _ in 0..<pages { app.buttons["Continue"].firstMatch.tap() }
        let start = app.buttons["Start Creating"].firstMatch
        if start.exists && start.isHittable { start.tap() } else { app.buttons["Skip"].firstMatch.tap() }
        for target in targets {
            app.tabBars.buttons[target].tap()
            XCTAssertEqual(app.state, .runningForeground, "Crashed tapping \(target): \(label)")
        }
    }

    @MainActor
    func testRepeatedTabSwitchesDontCrash() {
        let app = launch()
        for round in 0..<5 {
            for tab in tabs {
                app.tabBars.buttons[tab].tap()
                XCTAssertEqual(app.state, .runningForeground, "Crashed switching to \(tab) in round \(round)")
            }
        }
    }

    /// The owner's exact steps: Library → Settings → Show intro again → second page → Skip → Create, repeated.
    @MainActor
    func testSkippingTheIntroThenOpeningCreateDoesntCrash() {
        let app = launch()
        for round in 0..<5 {
            replayIntro(app, from: "Library", pages: 1, thenTap: ["Create"], "round \(round)")
        }
    }

    /// Skip from each intro page, then open each tab at once.
    @MainActor
    func testSkippingFromEveryPageThenEveryTab() {
        let app = launch()
        for pages in 0...2 {
            for target in tabs {
                replayIntro(app, from: "Library", pages: pages, thenTap: [target], "skip after \(pages) page(s), then \(target)")
            }
        }
    }

    /// Settings opened from every tab, then Skip and Create.
    @MainActor
    func testReopeningTheIntroFromEveryTab() {
        let app = launch()
        for start in tabs {
            replayIntro(app, from: start, pages: 1, thenTap: ["Create"], "from \(start)")
        }
    }

    /// Through every page to Start Creating, then each tab.
    @MainActor
    func testFinishingTheIntroThenEveryTab() {
        let app = launch()
        for target in tabs {
            replayIntro(app, from: "Library", pages: 3, thenTap: [target], "finish, then \(target)")
        }
    }

    /// Hopping between tabs with no pause while the intro is still fading out.
    @MainActor
    func testRapidTabHopsRightAfterSkipping() {
        let app = launch()
        for round in 0..<5 {
            replayIntro(app, from: "Library", pages: 1, thenTap: ["Create", "Explore", "Create", "Library"], "round \(round)")
        }
    }
}
