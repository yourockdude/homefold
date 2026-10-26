import XCTest

final class VoiceUITests: XCTestCase {
    private func launch(phrase: String? = nil, _ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        var args = ["-RYDemo", "-RYSkipBiometrics"]
        if let phrase { args += ["-RYVoicePhrase", phrase] }
        app.launchArguments = args + extra
        app.launch()
        return app
    }

    private func transcript(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["voice.transcript"] }

    /// Значение поля подставляется на следующем кадре после появления формы — ждём его.
    private func waitForValue(_ element: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "значение: \(String(describing: element.value))", file: file, line: line)
    }

    // MARK: Покупки

    /// Фраза разбирается в позиции, их можно проверить и добавить в список.
    func testShoppingByVoice() {
        let app = launch(phrase: "творог пятьсот грамм, кефир литр")
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()

        // Симулятор «слушает», затем список открывается на проверку.
        XCTAssertTrue(app.staticTexts["Проверьте список"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Творог"].exists && app.staticTexts["Кефир"].exists)
        XCTAssertTrue(app.staticTexts["500 г · Молочное и яйца"].exists)
        XCTAssertTrue(app.staticTexts["1 л · Молочное и яйца"].exists)
        XCTAssertTrue(app.buttons["voice.confirm"].label.contains("2"))
        app.buttons["voice.confirm"].tap()

        XCTAssertTrue(app.staticTexts["Творог"].waitForExistence(timeout: 5), "позиции в списке")
        XCTAssertTrue(app.staticTexts["Кефир"].exists)
        XCTAssertTrue(app.staticTexts["Осталось купить 8"].waitForExistence(timeout: 3))
    }

    func testRemovingItemBeforeAdding() {
        let app = launch(phrase: "творог, кефир, сыр")
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        XCTAssertTrue(app.staticTexts["Проверьте список"].waitForExistence(timeout: 15))
        app.buttons["voice.remove.1"].tap()
        XCTAssertFalse(app.staticTexts["Кефир"].exists)
        XCTAssertTrue(app.buttons["voice.confirm"].label.contains("2"))
        app.buttons["voice.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Сыр"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Кефир"].exists)
    }

    func testBackReturnsToRecordingAndKeepsText() {
        let app = launch(phrase: "творог")
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        XCTAssertTrue(app.buttons["voice.back"].waitForExistence(timeout: 15))
        app.buttons["voice.back"].tap()
        XCTAssertTrue(transcript(app).waitForExistence(timeout: 3))
        XCTAssertEqual(transcript(app).value as? String, "творог")
    }

    // MARK: Дела

    /// Дело открывается в обычной форме с заполненными полями.
    func testTaskByVoiceOpensPrefilledForm() {
        let app = launch(phrase: "завтра в 18:30 забрать Соню с танцев Михаилу")
        app.buttons["tab.tasks"].tap()
        app.buttons["tasks.voice"].tap()

        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "после записи открылась форма дела")
        waitForValue(title, "Забрать Соню с танцев")
        XCTAssertTrue(app.staticTexts["Распознано из фразы"].exists)
        XCTAssertTrue(app.staticTexts["Михаил"].exists, "ответственный распознан")
        app.buttons["sheet.cancel"].tap()
    }

    /// На бесплатном тарифе повтор не применяется, вместо него — подсказка и вход в пейвол.
    func testRecurrenceNeedsPlus() {
        let app = launch(phrase: "полить растения каждый день в 19:00")
        app.buttons["tab.tasks"].tap()
        app.buttons["tasks.voice"].tap()
        XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 20))
        waitForValue(app.textFields["task.title"], "Полить растения")
        XCTAssertTrue(app.staticTexts["Повтор «Ежедневно» доступен в HomeFold Plus — пока дело создастся без повтора."].exists)
        app.buttons["task.voiceUpgrade"].tap()
        XCTAssertTrue(app.buttons["paywall.purchase"].waitForExistence(timeout: 5))
    }

    // MARK: Нет микрофона

    func testDeniedMicrophoneStillAllowsTyping() {
        let app = launch(phrase: nil, ["-RYVoiceDenied"])
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        XCTAssertTrue(app.staticTexts["Нет доступа к микрофону"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voice.settings"].exists)
        XCTAssertFalse(app.buttons["voice.done"].isEnabled, "пока текста нет, разбирать нечего")

        let field = transcript(app)
        field.tap()
        field.typeText("творог, кефир")
        XCTAssertTrue(app.buttons["voice.done"].isEnabled)
        app.buttons["voice.done"].tap()
        XCTAssertTrue(app.staticTexts["Проверьте список"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Творог"].exists)
    }

    func testUnavailableRecognitionExplainsAndAllowsTyping() {
        let app = launch(phrase: nil, ["-RYVoiceUnavailable"])
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        XCTAssertTrue(app.staticTexts["Распознавание речи недоступно"].waitForExistence(timeout: 5))
        XCTAssertTrue(transcript(app).exists)
    }

    func testNothingRecognizedShowsHint() {
        let app = launch(phrase: nil, ["-RYVoiceUnavailable"])
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        let field = transcript(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("пожалуйста")
        app.buttons["voice.done"].tap()
        XCTAssertTrue(app.staticTexts["Ничего не разобрали"].waitForExistence(timeout: 3))
    }

    func testCancelClosesSheet() {
        let app = launch(phrase: nil, ["-RYVoiceUnavailable"])
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        XCTAssertTrue(app.buttons["voice.cancel"].waitForExistence(timeout: 5))
        app.buttons["voice.cancel"].tap()
        XCTAssertTrue(app.buttons["shopping.add"].waitForExistence(timeout: 3))
    }

    // MARK: Настоящий движок

    /// Регрессия: нажатие на микрофон с системным распознаванием не роняло приложение
    /// (колбэки запроса доступа приходят не на главном потоке). Доступ подтверждается системным окном.
    func testRealEngineDoesNotCrash() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"]   // без симулятора речи
        addUIInterruptionMonitor(withDescription: "Доступ к микрофону и речи") { alert in
            for title in ["OK", "ОК", "Разрешить", "Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()
        app.buttons["tab.shopping"].tap()
        app.buttons["shopping.voice"].tap()
        sleep(3)
        app.tap()   // даёт сработать монитору системных окон
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "приложение упало после нажатия на голосовой ввод")
        XCTAssertTrue(app.staticTexts["Список голосом"].exists)
        XCTAssertTrue(transcript(app).exists, "лист остаётся рабочим: текст можно ввести вручную")
    }
}
