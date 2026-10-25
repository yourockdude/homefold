import XCTest

final class PaywallUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"] + extra
        app.launch()
        return app
    }

    private func openPaywallFromSettings(_ app: XCUIApplication) {
        app.buttons["Настройки профиля"].tap()
        XCTAssertTrue(app.buttons["settings.subscription"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.subscription"].label, "Подключить")
        app.buttons["settings.subscription"].tap()
        XCTAssertTrue(app.staticTexts["HomeFold Plus"].waitForExistence(timeout: 3))
    }

    /// Пейвол: сравнение тарифов, два плана, покупка и экран успеха. После покупки тариф семьи — Plus.
    func testPurchaseYearlyActivatesPlus() {
        let app = launch()
        openPaywallFromSettings(app)
        XCTAssertTrue(app.otherElements["paywall.comparison"].exists || app.descendants(matching: .any)["paywall.comparison"].exists)
        XCTAssertTrue(app.buttons["paywall.plan.yearly"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["paywall.plan.monthly"].exists)
        XCTAssertTrue(app.staticTexts["−31%"].exists, "скидка годового тарифа")

        app.buttons["paywall.plan.monthly"].tap()
        XCTAssertTrue(app.buttons["paywall.purchase"].label.contains("299"))
        app.buttons["paywall.plan.yearly"].tap()
        XCTAssertTrue(app.buttons["paywall.purchase"].label.contains("2 490"))

        app.buttons["paywall.purchase"].tap()
        XCTAssertTrue(app.staticTexts["paywall.success"].waitForExistence(timeout: 5))
        app.buttons["paywall.done"].tap()

        // В настройках теперь «Управлять».
        XCTAssertTrue(app.buttons["settings.subscription"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["settings.subscription"].label, "Управлять")
    }

    /// Лимит участников снимается после покупки: форма приглашения открывается.
    func testPlusUnlocksMemberLimit() {
        let app = launch()
        app.descendants(matching: .any)["overview.cover"].tap()
        app.buttons["family.add"].tap()
        XCTAssertTrue(app.buttons["paywall.purchase"].waitForExistence(timeout: 3))
        app.buttons["paywall.purchase"].tap()
        XCTAssertTrue(app.buttons["paywall.done"].waitForExistence(timeout: 5))
        app.buttons["paywall.done"].tap()
        XCTAssertTrue(app.staticTexts["3 из 8 участников"].waitForExistence(timeout: 3))

        app.buttons["family.add"].tap()
        XCTAssertTrue(app.textFields["family.add.name"].waitForExistence(timeout: 3), "теперь форма, а не пейвол")
    }

    func testCancelledPurchaseStaysOnPaywall() {
        let app = launch(["-RYStoreCancel"])
        openPaywallFromSettings(app)
        app.buttons["paywall.purchase"].tap()
        XCTAssertFalse(app.staticTexts["paywall.success"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["paywall.purchase"].isEnabled, "после отмены можно попробовать снова")
        XCTAssertFalse(app.staticTexts["paywall.error"].exists)
    }

    func testFailedPurchaseShowsError() {
        let app = launch(["-RYStoreFail"])
        openPaywallFromSettings(app)
        app.buttons["paywall.purchase"].tap()
        XCTAssertTrue(app.staticTexts["Не удалось оформить подписку. Проверьте интернет и попробуйте ещё раз."].waitForExistence(timeout: 5))
    }

    func testRestoreWithoutSubscriptionExplains() {
        let app = launch()
        openPaywallFromSettings(app)
        app.buttons["paywall.restore"].tap()
        XCTAssertTrue(app.staticTexts["Действующей подписки HomeFold Plus не найдено."].waitForExistence(timeout: 5))
    }

    func testPlansLoadFailureOffersRetry() {
        let app = launch(["-RYStoreNoPlans"])
        openPaywallFromSettings(app)
        XCTAssertTrue(app.staticTexts["Не удалось загрузить тарифы"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paywall.retry"].exists)
        XCTAssertFalse(app.buttons["paywall.purchase"].isEnabled)
    }

    func testCloseDismissesPaywall() {
        let app = launch()
        openPaywallFromSettings(app)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.buttons["settings.subscription"].waitForExistence(timeout: 3))
    }
}
