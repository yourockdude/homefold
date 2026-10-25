import XCTest

final class PullToRefreshUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics", "-RYRefreshProbe"]
        app.launch()
        return app
    }

    /// Тянет экран вниз от верхней трети — так срабатывает системный pull-to-refresh.
    private func pull(_ app: XCUIApplication, hold: TimeInterval = 0.2) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        start.press(forDuration: hold, thenDragTo: end)
    }

    /// Число запущенных обновлений из отладочного счётчика.
    private func refreshCount(_ app: XCUIApplication) -> Int {
        Int(app.staticTexts["debug.refreshCount"].label) ?? -1
    }

    private func assertRefreshFired(_ app: XCUIApplication, from before: Int, file: StaticString = #filePath, line: UInt = #line) {
        let counter = app.staticTexts["debug.refreshCount"]
        let predicate = NSPredicate(format: "label != %@", String(before))
        expectation(for: predicate, evaluatedWith: counter)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(refreshCount(app), before + 1, "pull-to-refresh должен запускать ровно одно обновление", file: file, line: line)
    }

    private func save(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["RY_SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testOverviewRefreshKeepsContent() {
        let app = launch()
        XCTAssertTrue(app.buttons["Отметить выполненным: Забрать Соню с танцев"].waitForExistence(timeout: 5))
        let before = refreshCount(app)
        pull(app)
        assertRefreshFired(app, from: before)
        save("pull-overview")
        XCTAssertTrue(app.buttons["Отметить выполненным: Забрать Соню с танцев"].waitForExistence(timeout: 3))
    }

    func testShoppingRefreshKeepsContent() {
        let app = launch()
        app.buttons["tab.shopping"].tap()
        XCTAssertTrue(app.staticTexts["Общий список семьи Смирновых"].waitForExistence(timeout: 5))
        let before = refreshCount(app)
        pull(app)
        assertRefreshFired(app, from: before)
        save("pull-shopping")
        XCTAssertTrue(app.buttons["shopping.add"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Осталось купить 6"].exists)
    }

    func testTasksRefreshKeepsContent() {
        let app = launch()
        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(app.staticTexts["Дела семьи"].waitForExistence(timeout: 5))
        let before = refreshCount(app)
        pull(app)
        assertRefreshFired(app, from: before)
        save("pull-tasks")
        XCTAssertTrue(app.buttons["tasks.add"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3 дела"].exists)
    }

    func testDocumentsRefreshKeepsContent() {
        let app = launch()
        app.buttons["tab.documents"].tap()
        XCTAssertTrue(app.staticTexts["Документы"].waitForExistence(timeout: 5))
        let before = refreshCount(app)
        pull(app)
        assertRefreshFired(app, from: before)
        save("pull-documents")
        XCTAssertTrue(app.buttons["category.personal"].waitForExistence(timeout: 3))
    }

    /// В состоянии «Нет связи» обновление не стирает сохранённые данные и не убирает баннер (сервера нет).
    func testRefreshInOfflineStateKeepsBanner() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics", "-RYOverviewOffline", "-RYRefreshProbe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Нет связи · данные сохранены"].waitForExistence(timeout: 5))
        let before = Int(app.staticTexts["debug.refreshCount"].label) ?? -1
        pull(app)
        let counter = app.staticTexts["debug.refreshCount"]
        expectation(for: NSPredicate(format: "label != %@", String(before)), evaluatedWith: counter)
        waitForExpectations(timeout: 4)
        sleep(1)
        XCTAssertTrue(app.staticTexts["Нет связи · данные сохранены"].exists)
        XCTAssertTrue(app.buttons["Отметить выполненным: Забрать Соню с танцев"].exists)
    }
}
