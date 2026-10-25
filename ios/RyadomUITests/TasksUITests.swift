import XCTest

final class TasksUITests: XCTestCase {
    private var app: XCUIApplication!
    private let cal = Calendar.current

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-RYDemo"]
        app.launch()
        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(app.staticTexts["Дела семьи"].waitForExistence(timeout: 5))
    }

    func testListShowsTodayAndOverdue() {
        XCTAssertTrue(app.staticTexts["3 дела"].exists)
        XCTAssertTrue(app.staticTexts["Просрочено"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Забрать Соню с танцев'")).firstMatch.exists)
    }

    func testCreateTask() {
        app.buttons["tasks.add"].tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.typeText("Купить подарок")
        app.buttons["task.submit"].tap()
        XCTAssertTrue(app.staticTexts["4 дела"].waitForExistence(timeout: 3))
    }

    func testEmptyTitleShowsError() {
        app.buttons["tasks.add"].tap()
        app.buttons["task.submit"].tap()
        XCTAssertTrue(app.staticTexts["Введите название дела."].waitForExistence(timeout: 2))
    }

    func testCompleteFromListUpdatesCounter() {
        app.buttons["Отметить выполненным: Сверить показания счётчиков"].tap()
        XCTAssertTrue(app.staticTexts["2 дела"].waitForExistence(timeout: 2))
    }

    func testChecklistToggleInDetail() {
        openDetail("Забрать Соню с танцев")
        XCTAssertTrue(app.staticTexts["1 из 2"].waitForExistence(timeout: 2))
        app.buttons["Взять бутылку воды"].tap()
        XCTAssertTrue(app.staticTexts["2 из 2"].waitForExistence(timeout: 2))
    }

    func testCompleteAndReopenInDetail() {
        openDetail("Сверить показания счётчиков")
        app.buttons["task.complete"].tap()
        XCTAssertTrue(app.staticTexts["Выполнено"].waitForExistence(timeout: 2))
        app.buttons["task.reopen"].tap()
        XCTAssertTrue(app.buttons["task.complete"].waitForExistence(timeout: 2))
    }

    func testOverdueRescheduleKeepsTaskOpen() {
        openDetail("Продлить страховку квартиры")
        XCTAssertTrue(app.staticTexts["Выберите новый срок"].waitForExistence(timeout: 2))
        app.buttons["task.saveReschedule"].tap()
        XCTAssertFalse(app.staticTexts["Выберите новый срок"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["task.complete"].exists, "перенос не должен отмечать дело выполненным")
    }

    func testEmptyDayState() {
        // Ищем в ленте недели день без дел: повторяющееся дело и просроченное занимают не все дни.
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day.'"))
        var found = false
        for index in 0..<days.count {
            let day = days.element(boundBy: index)
            if day.isSelected { continue }
            day.tap()
            if app.staticTexts["День свободен"].waitForExistence(timeout: 1) { found = true; break }
        }
        XCTAssertTrue(found, "в неделе должен быть свободный день")
        XCTAssertTrue(app.staticTexts["0 дел"].exists)
    }

    private func openDetail(_ title: String) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }
}
