import XCTest

/// Снимает состояния экрана «Покупки» для сверки с макетом. Папка задаётся переменной окружения.
final class ShoppingScreenshotTests: XCTestCase {
    private func save(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["RY_SHOTS_DIR"] ?? UserDefaults.standard.string(forKey: "RY_SHOTS_DIR") else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testCaptureStates() {
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo"]
        app.launch()
        app.buttons["tab.shopping"].tap()
        _ = app.staticTexts["Осталось купить 6"].waitForExistence(timeout: 3)
        save("1-list")
        app.buttons["shopping.menu"].tap()
        sleep(1)
        save("2-menu-open")
        print("MENU:", app.buttons.allElementsBoundByIndex.map { $0.label })
        app.buttons["Убрать купленные"].tap()
        sleep(1)
        save("3-after-menu-tap")
        print("AFTER:", app.buttons.allElementsBoundByIndex.map { $0.label })
    }
}
