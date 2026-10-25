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

    func testCancelSheetDoesNotAddItem() {
        app.buttons["shopping.add"].tap()
        let name = app.textFields["item.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Огурцы")
        app.buttons["sheet.cancel"].tap()
        XCTAssertTrue(app.staticTexts["Осталось купить 6"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Огурцы"].exists)
    }

    func testStepperChangesQuantity() {
        app.buttons["shopping.add"].tap()
        let name = app.textFields["item.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Сок")
        app.buttons["item.plus"].tap()
        app.buttons["item.plus"].tap()
        XCTAssertEqual(app.textFields["item.quantity"].value as? String, "3")
        app.buttons["item.submit"].tap()
        XCTAssertTrue(app.staticTexts["3 шт."].waitForExistence(timeout: 3))
    }

    func testAllBoughtThenNewListShowsEmptyState() {
        for name in ["Молоко 3,2%", "Яйца С1", "Яблоки", "Помидоры", "Хлеб на закваске", "Кофе в зёрнах"] {
            app.buttons["Отметить купленным: \(name)"].tap()
        }
        XCTAssertTrue(app.staticTexts["Всё куплено"].waitForExistence(timeout: 3))
        app.buttons["shopping.newList"].tap()
        XCTAssertTrue(app.staticTexts["Что нужно купить?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["shopping.add"].exists)
    }
}
