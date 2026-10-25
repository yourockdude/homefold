import XCTest

final class DocumentsUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-RYDemo", "-RYSkipBiometrics"] + extra
        app.launch()
        app.buttons["tab.documents"].tap()
        XCTAssertTrue(app.staticTexts["Документы"].waitForExistence(timeout: 5))
        return app
    }

    func testStorageShowsShelvesAndRecent() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Важное всегда под рукой · 6 файлов"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["category.personal"].exists)
        XCTAssertTrue(app.buttons["category.personal"].label.contains("3 документа"))
        XCTAssertTrue(app.buttons["document.row.Полис ДМС · Соня"].exists)
    }

    func testSearchWithoutResultsAndClear() {
        let app = launch()
        let field = app.textFields["documents.search"]
        field.tap()
        field.typeText("Свидетельство")
        XCTAssertTrue(app.staticTexts["Ничего не нашлось"].waitForExistence(timeout: 3))
        app.buttons["Очистить поиск"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category.personal"].waitForExistence(timeout: 3))
    }

    func testSearchByOwnerName() {
        let app = launch()
        let field = app.textFields["documents.search"]
        field.tap()
        field.typeText("Соня")
        XCTAssertTrue(app.buttons["document.row.Полис ДМС · Соня"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["document.row.СНИЛС · Соня"].exists)
        XCTAssertFalse(app.buttons["document.row.Паспорт · Михаил"].exists)
    }

    func testEmptyStorageState() {
        let app = launch(["-RYEmptyDocuments"])
        XCTAssertTrue(app.staticTexts["Важное найдёт своё место"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["documents.addFirst"].exists)
    }

    func testFormValidation() {
        let app = launch()
        app.buttons["documents.plus"].tap()
        app.buttons["document.submit"].tap()
        XCTAssertTrue(app.staticTexts["Введите название документа."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Выберите файл или отсканируйте документ."].exists)
    }

    func testAddDocumentUploadsAndShowsSuccess() {
        let app = launch(["-RYPrefillFile"])
        app.buttons["documents.plus"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Выбран: spravka.pdf'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["document.submit"].tap()
        XCTAssertTrue(app.staticTexts["Сохраняем важное"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Документ загружен"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["В хранилище 7 файлов · Здоровье: 2"].exists)
        app.buttons["document.backToList"].tap()
        XCTAssertTrue(app.staticTexts["Важное всегда под рукой · 7 файлов"].waitForExistence(timeout: 3))
    }

    func testUploadFailureThenRetrySucceeds() {
        let app = launch(["-RYPrefillFile", "-RYUploadFail"])
        app.buttons["documents.plus"].tap()
        app.buttons["document.submit"].tap()
        XCTAssertTrue(app.staticTexts["Не удалось загрузить файл"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Проверьте интернет и повторите загрузку."].exists)
        app.buttons["upload.retry"].tap()
        XCTAssertTrue(app.staticTexts["Документ загружен"].waitForExistence(timeout: 15))
    }

    func testCancelUploadDoesNotAddDocument() {
        let app = launch(["-RYPrefillFile", "-RYUploadHold"])
        app.buttons["documents.plus"].tap()
        app.buttons["document.submit"].tap()
        XCTAssertTrue(app.staticTexts["64%"].waitForExistence(timeout: 10))
        app.buttons["upload.cancel"].tap()
        XCTAssertTrue(app.staticTexts["Важное всегда под рукой · 6 файлов"].waitForExistence(timeout: 3))
    }

    func testCameraDeniedScreen() {
        let app = launch(["-RYCameraDenied"])
        app.buttons["documents.plus"].tap()
        app.buttons["document.scan"].tap()
        XCTAssertTrue(app.staticTexts["Нужен доступ к камере"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera.openSettings"].exists)
        XCTAssertTrue(app.buttons["camera.pickFile"].exists)
    }

    func testDetailShowsMetadata() {
        let app = launch()
        app.buttons["document.row.Полис ДМС · Соня"].tap()
        XCTAssertTrue(app.staticTexts["7428 1053 609"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["31 августа 2027"].exists)
        XCTAssertTrue(app.staticTexts["Доступен семье Смирновых"].exists)
        XCTAssertTrue(app.buttons["document.share"].exists)
    }
}
