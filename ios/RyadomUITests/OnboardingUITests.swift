import XCTest

final class OnboardingUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYFreshInstall", "-RYSkipSplash"]
        app.launch()
        return app
    }

    /// Все слайды по порядку, на последнем «Начать» ведёт к созданию семьи.
    func testSlidesThenFamilyCreation() {
        let app = launch()
        let titles = ["Покупки — вся семья в курсе", "Дела без забывчивости", "Документы под рукой",
                      "Защита Face ID", "Работает без интернета"]
        XCTAssertTrue(app.staticTexts[titles[0]].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
        for title in titles.dropFirst() {
            app.buttons["onboarding.next"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3), title)
        }
        XCTAssertEqual(app.buttons["onboarding.next"].label, "Начать")
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, "на последнем слайде пропускать нечего")
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Добавьте семью"].waitForExistence(timeout: 3))
    }

    func testSkipGoesToFamilyCreation() {
        let app = launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["Добавьте семью"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
    }

    /// Свайп влево листает слайды.
    func testSwipeChangesSlide() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Покупки — вся семья в курсе"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Дела без забывчивости"].waitForExistence(timeout: 3))
    }
}
