import XCTest

final class TabTransitionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()
        return app
    }

    /// После перехода экран прежней вкладки не остаётся в дереве доступности (VoiceOver не видит скрытое).
    func testHiddenTabsAreNotAccessible() {
        let app = launch()
        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(app.staticTexts["Дела семьи"].waitForExistence(timeout: 5))
        app.buttons["tab.overview"].tap()
        XCTAssertTrue(app.buttons["Отметить выполненным: Забрать Соню с танцев"].waitForExistence(timeout: 3))
        // «Дела семьи» теперь на скрытой вкладке — в дереве доступности его быть не должно.
        let hidden = app.staticTexts["Дела семьи"]
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: hidden)
        waitForExpectations(timeout: 3)
    }

    func testTabBarSelectionTraitFollowsSelection() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab.overview"].isSelected)
        app.buttons["tab.documents"].tap()
        XCTAssertTrue(app.staticTexts["Документы"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.documents"].isSelected)
        XCTAssertFalse(app.buttons["tab.overview"].isSelected)
    }
}
