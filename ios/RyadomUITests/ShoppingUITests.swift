import XCTest

final class ShoppingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-RYDemo"]
        app.launch()
        app.buttons["tab.shopping"].tap()
    }

    func testAddItemAppearsInList() {
        app.buttons["shopping.add"].tap()
        let name = app.textFields["item.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Огурцы")
        app.buttons["item.submit"].tap()
        XCTAssertTrue(app.staticTexts["Огурцы"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Осталось купить 7"].exists)
    }

    func testEmptyNameShowsError() {
        app.buttons["shopping.add"].tap()
        app.buttons["item.submit"].tap()
        XCTAssertTrue(app.staticTexts["Введите название, чтобы добавить покупку."].waitForExistence(timeout: 2))
    }

    func testMarkBoughtUpdatesCounter() {
        app.buttons["Отметить купленным: Молоко 3,2%"].tap()
        XCTAssertTrue(app.staticTexts["Осталось купить 5"].waitForExistence(timeout: 2))
    }

    func testDeleteWithConfirmationAndUndo() {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Кофе в зёрнах'")).firstMatch.tap()
        app.buttons["item.delete"].tap()
        app.buttons["Удалить"].tap()
        XCTAssertTrue(app.staticTexts["Кофе в зёрнах удалён"].waitForExistence(timeout: 2))
        app.buttons["Отменить"].tap()
        XCTAssertTrue(app.staticTexts["Осталось купить 6"].waitForExistence(timeout: 2))
    }
}
