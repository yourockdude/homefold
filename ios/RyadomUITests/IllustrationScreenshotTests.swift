import XCTest

/// Снимает экраны с иллюстрациями (каталог — TEST_RUNNER_RY_SHOTS_DIR).
final class IllustrationScreenshotTests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo"] + extra
        app.launch()
        return app
    }

    private func save(_ name: String) {
        sleep(1)
        guard let dir = ProcessInfo.processInfo.environment["RY_SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testBasketEmptyShopping() {
        let app = launch(["-RYSkipBiometrics", "-RYEmptyShopping"])
        app.buttons["tab.shopping"].tap()
        XCTAssertTrue(app.staticTexts["Что нужно купить?"].waitForExistence(timeout: 5))
        save("ill-basket")
    }

    func testMagnifierSearch() {
        let app = launch(["-RYSkipBiometrics"])
        app.buttons["tab.documents"].tap()
        let field = app.textFields["documents.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Свидетельство")
        XCTAssertTrue(app.staticTexts["Ничего не нашлось"].waitForExistence(timeout: 3))
        save("ill-search")
    }

    func testLockLockedDocuments() {
        let app = launch(["-RYDenyBiometrics", "-documentsProtection", "YES"])
        app.buttons["tab.documents"].tap()
        XCTAssertTrue(app.staticTexts["Документы защищены"].waitForExistence(timeout: 5))
        save("ill-lock")
    }

    func testCameraDenied() {
        let app = launch(["-RYSkipBiometrics", "-RYCameraDenied"])
        app.buttons["tab.documents"].tap()
        app.buttons["documents.plus"].tap()
        app.buttons["document.scan"].tap()
        XCTAssertTrue(app.staticTexts["Нужен доступ к камере"].waitForExistence(timeout: 5))
        save("ill-camera")
    }

    func testCalendarEmptyDay() {
        let app = launch(["-RYSkipBiometrics"])
        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(app.staticTexts["Дела семьи"].waitForExistence(timeout: 5))
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day.'"))
        for index in 0..<days.count {
            let day = days.element(boundBy: index)
            if day.isSelected { continue }
            day.tap()
            if app.staticTexts["День свободен"].waitForExistence(timeout: 1) { break }
        }
        XCTAssertTrue(app.staticTexts["День свободен"].exists)
        save("ill-calendar")
    }

    func testCloudOverviewError() {
        let app = launch(["-RYSkipBiometrics", "-RYOverviewError"])
        XCTAssertTrue(app.staticTexts["Не удалось загрузить обзор"].waitForExistence(timeout: 5))
        save("ill-cloud")
    }
}
