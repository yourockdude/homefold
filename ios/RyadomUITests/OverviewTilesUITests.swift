import XCTest

final class OverviewTilesUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()
        return app
    }

    /// Плитка «Купить» открывает вкладку «Покупки».
    func testShoppingTileOpensShopping() {
        let app = launch()
        let tile = app.buttons["overview.tile.shopping"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.label.hasPrefix("Купить: 6"), tile.label)
        tile.tap()
        XCTAssertTrue(app.buttons["shopping.add"].waitForExistence(timeout: 5), "открылся список покупок")
        XCTAssertTrue(app.buttons["tab.shopping"].isSelected)
    }

    /// Плитка «Сегодня» открывает вкладку «Дела».
    func testTodayTileOpensTasks() {
        let app = launch()
        let tile = app.buttons["overview.tile.tasks"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.buttons["tasks.add"].waitForExistence(timeout: 5), "открылись дела")
        XCTAssertTrue(app.buttons["tab.tasks"].isSelected)
    }
}
