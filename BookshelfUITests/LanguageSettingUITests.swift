import XCTest

/// 言語（設定の「言語」: システムに合わせる・日本語・English。2026-11-19 オーナー指示）。
/// 選ぶとチェックが移り、いまと違う言語を選ぶと「開き直すと切り替わる」と知らせる
@MainActor
final class LanguageSettingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testChoosingALanguageShowsRelaunchNote() {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.japanese + ["-UITestReset", "-SeedBooks", "小説:3"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        app.buttons["browse.display"].tap()
        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 5))
        app.buttons["menu.settings"].tap()

        let system = app.buttons["settings.language.system"]
        let english = app.buttons["settings.language.en"]
        let note = app.staticTexts["settings.language.note"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        XCTAssertTrue(system.isSelected, "初期値はシステムに合わせる")
        XCTAssertEqual(english.label, "English")
        XCTAssertTrue(note.label.contains("開き直したとき"))

        english.tap()
        XCTAssertTrue(english.isSelected)
        XCTAssertFalse(system.isSelected)
        XCTAssertTrue(note.label.contains("切り替わります"), note.label)

        // いまの言語（システム）に戻すと、知らせも元に戻る
        system.tap()
        XCTAssertTrue(system.isSelected)
        XCTAssertTrue(note.label.contains("開き直したとき"), note.label)
    }
}
