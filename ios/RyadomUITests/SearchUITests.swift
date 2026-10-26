import XCTest

final class SearchUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics", "-RYClearSearchHistory"] + extra
        app.launch()
        return app
    }

    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["Поиск"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        return field
    }

    func testIdleStateAndCancel() {
        let app = launch()
        _ = openSearch(app)
        XCTAssertTrue(app.staticTexts["Поиск по HomeFold"].waitForExistence(timeout: 3))
        app.buttons["search.cancel"].tap()
        XCTAssertTrue(app.buttons["Поиск"].waitForExistence(timeout: 3))
    }

    func testFindsShoppingAndOpensItem() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("молок")
        XCTAssertTrue(app.staticTexts["Покупки"].waitForExistence(timeout: 3))
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Молоко 3,2%'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        // Открылась вкладка «Покупки» и карточка товара.
        XCTAssertTrue(app.textFields["item.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["item.name"].value as? String, "Молоко 3,2%")
    }

    func testYoAndCaseInsensitiveTaskSearchOpensTask() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("СЧЕТЧИКОВ")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Сверить показания счётчиков'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Сверить показания счётчиков"].waitForExistence(timeout: 5), "открылась карточка дела")
    }

    func testFindsDocumentAndOpensIt() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("полис")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Полис ДМС'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.staticTexts["Полис ДМС · Соня"].waitForExistence(timeout: 5), "открылась карточка документа")
    }

    func testNothingFoundShowsEmptyState() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("zzzzqq")
        XCTAssertTrue(app.staticTexts["Ничего не найдено"].waitForExistence(timeout: 3))
        app.buttons["search.clear"].tap()
        XCTAssertTrue(app.staticTexts["Поиск по HomeFold"].waitForExistence(timeout: 3))
    }

    func testRecentQueryIsRemembered() {
        let app = launch()
        var field = openSearch(app)
        field.typeText("яблок")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Яблоки'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.textFields["item.name"].waitForExistence(timeout: 5))
        app.buttons["sheet.cancel"].tap()
        app.buttons["tab.overview"].tap()
        field = openSearch(app)
        XCTAssertTrue(app.staticTexts["Недавние запросы"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["search.recent"].firstMatch.exists)
    }
}
