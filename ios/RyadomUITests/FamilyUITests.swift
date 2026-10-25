import XCTest

final class FamilyUITests: XCTestCase {
    /// Первый запуск: вместо вкладок — создание семьи; после него открывается «Обзор» с этой семьёй.
    func testFirstLaunchCreatesFamily() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYFreshInstall", "-RYSkipSplash"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Создайте семью"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab.overview"].exists)

        app.buttons["onboarding.create"].tap()
        XCTAssertTrue(app.staticTexts["Введите имя"].exists, "пустая форма не создаёт семью")

        let name = app.textFields["onboarding.name"]
        name.tap(); name.typeText("Анна")
        let family = app.textFields["onboarding.family"]
        family.tap(); family.typeText("Смирновы")
        app.buttons["onboarding.create"].tap()

        XCTAssertTrue(app.buttons["tab.overview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Смирновы"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ', Анна'")).firstMatch.exists)
    }

    /// Карточка семьи открывает «Моя семья»: приглашение и удаление участника.
    func testInviteAndRemoveMember() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]
        app.launch()

        let cover = app.descendants(matching: .any)["overview.cover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        XCTAssertTrue(app.staticTexts["Моя семья"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3 из 3 участников"].exists || app.staticTexts["family.count"].exists)

        // На free уже 3 из 3: приглашение упирается в лимит тарифа.
        app.buttons["family.add"].tap()
        let field = app.textFields["family.add.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Бабушка")
        app.buttons["family.add.confirm"].tap()
        XCTAssertTrue(app.staticTexts["В вашем тарифе до 3 участников."].waitForExistence(timeout: 3))
        app.buttons["sheet.cancel"].tap()

        // Освобождаем место: убираем Соню.
        app.buttons["family.remove.Соня"].tap()
        app.buttons["Убрать"].tap()
        XCTAssertFalse(app.buttons["family.remove.Соня"].waitForExistence(timeout: 2))

        app.buttons["family.add"].tap()
        let field2 = app.textFields["family.add.name"]
        XCTAssertTrue(field2.waitForExistence(timeout: 3))
        field2.typeText("Бабушка")
        app.buttons["family.add.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Бабушка"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Приглашён · ждёт подтверждения"].exists)
    }
}
