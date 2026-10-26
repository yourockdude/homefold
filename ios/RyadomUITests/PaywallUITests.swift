import XCTest

final class PaywallUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"] + extra
        app.launch()
        return app
    }

    /// Пейвол из настроек (пробный период идёт).
    private func openPaywallFromSettings(_ app: XCUIApplication) {
        app.buttons["Настройки профиля"].tap()
        XCTAssertTrue(app.buttons["settings.subscription"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.subscription"].label, "Подключить")
        app.buttons["settings.subscription"].tap()
        XCTAssertTrue(app.staticTexts["HomeFold Plus"].waitForExistence(timeout: 3))
    }

    // MARK: Пробный период

    func testNewFamilyHasTwoWeeksAndNoBanner() {
        let app = launch()
        XCTAssertTrue(app.buttons["Настройки профиля"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["overview.trialBanner"].exists, "баннер появляется только в последнюю неделю")
        app.buttons["Настройки профиля"].tap()
        XCTAssertTrue(app.staticTexts["Пробный период"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Осталось 14 дней, затем нужна подписка"].exists)
    }

    func testBannerAppearsInLastWeekAndOpensPaywall() {
        let app = launch(["-RYTrialDaysLeft", "3"])
        let banner = app.buttons["overview.trialBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.hasPrefix("Пробный период: осталось 3 дня"), banner.label)
        banner.tap()
        XCTAssertTrue(app.staticTexts["Пробный период: осталось 3 дня"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["paywall.close"].exists, "во время пробного периода пейвол можно закрыть")
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 3))
    }

    func testPaywallShowsBenefitsAndPlans() {
        let app = launch()
        openPaywallFromSettings(app)
        XCTAssertTrue(app.descendants(matching: .any)["paywall.benefits"].exists)
        XCTAssertTrue(app.staticTexts["До 8 участников"].exists && app.staticTexts["Повторяющиеся дела"].exists)
        XCTAssertTrue(app.buttons["paywall.plan.yearly"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["paywall.plan.monthly"].exists)
        XCTAssertTrue(app.staticTexts["−31%"].exists, "скидка годового тарифа")
        app.buttons["paywall.plan.monthly"].tap()
        XCTAssertTrue(app.buttons["paywall.purchase"].label.contains("299"))
        app.buttons["paywall.plan.yearly"].tap()
        XCTAssertTrue(app.buttons["paywall.purchase"].label.contains("2 490"))
    }

    func testPurchaseFromTrialActivatesPlus() {
        let app = launch(["-RYTrialDaysLeft", "5"])
        openPaywallFromSettings(app)
        app.buttons["paywall.purchase"].tap()
        XCTAssertTrue(app.staticTexts["paywall.success"].waitForExistence(timeout: 5))
        app.buttons["paywall.done"].tap()
        XCTAssertTrue(app.buttons["settings.subscription"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["settings.subscription"].label, "Управлять")
        XCTAssertTrue(app.staticTexts["HomeFold Plus"].exists)
    }

    func testSubscribedFamilyHasNoBannerAndShowsPlus() {
        let app = launch(["-RYSubscribed"])
        XCTAssertTrue(app.buttons["Настройки профиля"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["overview.trialBanner"].exists)
        app.buttons["Настройки профиля"].tap()
        XCTAssertEqual(app.buttons["settings.subscription"].label, "Управлять")
    }

    // MARK: Пробный период закончился

    func testExpiredTrialBlocksTheAppUntilSubscribed() {
        let app = launch(["-RYTrialDaysLeft", "0"])
        XCTAssertTrue(app.staticTexts["Пробный период закончился"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paywall.close"].exists, "закрыть нельзя")
        XCTAssertFalse(app.buttons["tab.shopping"].isHittable, "приложение под пейволом недоступно")
        XCTAssertTrue(app.buttons["paywall.restore"].exists)

        app.buttons["paywall.purchase"].tap()
        // После покупки пейвол уходит сам: доступ вернулся.
        XCTAssertTrue(app.buttons["tab.shopping"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Пробный период закончился"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.shopping"].isHittable)
    }

    func testExpiredPaywallRestoreWithoutSubscriptionExplains() {
        let app = launch(["-RYTrialDaysLeft", "0"])
        XCTAssertTrue(app.buttons["paywall.restore"].waitForExistence(timeout: 5))
        app.buttons["paywall.restore"].tap()
        XCTAssertTrue(app.staticTexts["Действующей подписки HomeFold Plus не найдено."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Пробный период закончился"].exists, "блокировка остаётся")
    }

    // MARK: Ошибки покупки

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
