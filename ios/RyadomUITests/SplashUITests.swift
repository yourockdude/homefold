import XCTest

final class SplashUITests: XCTestCase {
    /// Сплэш виден при запуске, затем растворяется, и рабочие экраны становятся доступны.
    func testSplashShowsThenDissolvesIntoApp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYShowSplash", "-RYSkipBiometrics"]
        app.launch()

        let splash = app.descendants(matching: .any)["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 3), "сплэш должен быть виден сразу после запуска")
        XCTAssertFalse(app.buttons["tab.overview"].isHittable, "пока идёт сплэш, экраны под ним недоступны")

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: splash)
        waitForExpectations(timeout: 8)

        XCTAssertTrue(app.buttons["tab.overview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Доброе утро, Анна"].exists || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Добр'")).firstMatch.exists)
    }

    /// На «Обзоре» логотипа больше нет: он только на сплэше.
    func testOverviewHasNoBrandMark() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()
        XCTAssertTrue(app.buttons["Отметить выполненным: Забрать Соню с танцев"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["рядом"].exists)
    }
}
