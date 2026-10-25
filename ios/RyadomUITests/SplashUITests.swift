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

    /// На «Обзоре» есть логотип и вход в настройки профиля; настройки сохраняются и закрываются.
    func testOverviewShowsBrandMarkAndOpensSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()
        XCTAssertTrue(app.buttons["Отметить выполненным: Забрать Соню с танцев"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["рядом"].exists)

        app.buttons["Настройки профиля"].tap()
        XCTAssertTrue(app.staticTexts["Настройки"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Защита документов"].exists)
        XCTAssertFalse(app.buttons["settings.save"].isEnabled, "без изменений сохранять нечего")

        let faceID = app.switches["settings.faceID"]
        XCTAssertTrue(faceID.exists)
        faceID.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["settings.save"].isEnabled)
        app.buttons["settings.save"].tap()
        XCTAssertTrue(app.staticTexts["рядом"].waitForExistence(timeout: 3), "после сохранения возвращаемся на обзор")
    }
}
