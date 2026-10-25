import XCTest

/// Снимает состояния экрана «Покупки» для сверки с макетом (каталог — TEST_RUNNER_RY_SHOTS_DIR).
final class ShoppingScreenshotTests: XCTestCase {
    private func save(_ name: String) {
        sleep(1)
        guard let dir = ProcessInfo.processInfo.environment["RY_SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testCaptureStates() {
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()
        app.buttons["tab.shopping"].tap()
        _ = app.staticTexts["Покупки"].waitForExistence(timeout: 5)
        save("s1-list")
        app.buttons["shopping.boughtToggle"].tap()
        save("s2-bought-expanded")
        app.buttons["shopping.boughtToggle"].tap()

        app.buttons["shopping.add"].tap()
        _ = app.textFields["item.name"].waitForExistence(timeout: 3)
        app.buttons["Михаил"].tap()
        app.textFields["item.name"].typeText("Огурцы")
        save("s3-form-add")
        app.buttons["sheet.cancel"].tap()

        app.buttons["shopping.add"].tap()
        _ = app.textFields["item.name"].waitForExistence(timeout: 3)
        app.buttons["item.submit"].tap()
        save("s4-form-error")
        app.buttons["sheet.cancel"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Молоко 3,2%'")).firstMatch.tap()
        _ = app.textFields["item.name"].waitForExistence(timeout: 3)
        save("s5-form-edit")
        app.buttons["sheet.cancel"].tap()
    }

    func testCaptureEndStates() {
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()
        app.buttons["tab.shopping"].tap()
        _ = app.staticTexts["Покупки"].waitForExistence(timeout: 5)

        // Тост удаления
        let coffee = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Кофе в зёрнах'")).firstMatch
        XCTAssertTrue(coffee.isHittable)
        coffee.tap()
        if !app.buttons["sheet.cancel"].waitForExistence(timeout: 3) { coffee.tap() }
        _ = app.buttons["item.delete"].waitForExistence(timeout: 3)
        app.buttons["item.delete"].tap()
        app.buttons["dialog.confirm"].tap()
        save("s7-toast")

        // Всё куплено
        for name in ["Молоко 3,2%", "Яйца С1", "Яблоки", "Помидоры", "Хлеб на закваске"] {
            app.buttons["Отметить купленным: \(name)"].tap()
        }
        save("s8-all-bought")

        // Пустой список
        app.buttons["shopping.newList"].tap()
        save("s9-empty")
    }
}
