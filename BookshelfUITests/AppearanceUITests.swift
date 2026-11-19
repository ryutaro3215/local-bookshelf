import XCTest

/// 外観（設定の「外観」: システムに合わせる・ライト・ダーク。2026-11-19 オーナー指示）。
/// ダークで主な画面を開き、スクリーンショットを結果（xcresult）に残す。環境変数 BOOKSHELF_SHOTS_DIR があればそこにも書き出す
/// （xcodebuild には TEST_RUNNER_BOOKSHELF_SHOTS_DIR=… で渡す）。題名は DebugSeed の架空のもの
@MainActor
final class AppearanceUITests: XCTestCase {
    private static let seed = "小説:3,エッセイ:2,哲学・思想:2+1"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.japanese + ["-UITestReset", "-SeedBooks", Self.seed] + extra
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "dark_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["BOOKSHELF_SHOTS_DIR"], !folder.isEmpty {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(
                to: URL(fileURLWithPath: folder).appendingPathComponent("dark_\(name).png"))
        }
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["browse.display"].tap()
        let menu = element(app, "menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(element(app, "settings.title").waitForExistence(timeout: 5))
    }

    /// 設定で外観を選ぶとチェックが移り、アプリを閉じても残る
    func testAppearanceSettingIsSavedAndSelected() {
        let app = launch()
        openSettings(app)
        let system = app.buttons["settings.appearance.system"]
        let dark = app.buttons["settings.appearance.dark"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        XCTAssertTrue(system.isSelected, "初期値はシステムに合わせる")
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        XCTAssertFalse(system.isSelected)
        shot(app, "F-1_settings")
        app.buttons["settings.appearance.light"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.light"].isSelected)
    }

    /// ダークで主な画面を開く（文字と地が同じ色にならないかは、書き出したスクリーンショットで確かめる）
    func testDarkScreens() {
        let app = launch(["-UITestAppearance", "dark"])
        shot(app, "Q-1_browse")

        // 棚の名前 → 棚を選ぶシート（地と文字が両方黒くなっていた）
        app.buttons["shelf.title"].tap()
        XCTAssertTrue(app.buttons["picker.row.小説"].waitForExistence(timeout: 5))
        shot(app, "G-3_picker")
        app.buttons["picker.row.エッセイ"].tap()
        let title = app.buttons["shelf.title"]
        let predicate = NSPredicate(format: "label == 'エッセイ'")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: title)], timeout: 10),
            .completed)

        // 表示メニュー・設定・ジャンル管理
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu").waitForExistence(timeout: 5))
        shot(app, "G-2_menu")
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        shot(app, "F-1_settings")
        app.buttons["settings.genres"].tap()
        XCTAssertTrue(element(app, "genres.title").waitForExistence(timeout: 5))
        shot(app, "F-2_genres")
        app.buttons["genres.back"].tap()
        app.buttons["settings.back"].tap()

        // 詳細・編集
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
        shot(app, "Q-3_detail")
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.buttons["edit.cancel"].waitForExistence(timeout: 5))
        shot(app, "E-6_edit")
        app.buttons["edit.cancel"].tap()
        app.buttons["detail.back"].tap()

        // 検索
        app.buttons["browse.search"].tap()
        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("灰色")
        shot(app, "E-4_search")
        app.buttons["search.cancel"].tap()

        // 登録方法のシート
        app.buttons["browse.add"].tap()
        XCTAssertTrue(app.buttons["register.camera"].waitForExistence(timeout: 5))
        shot(app, "A-2_register")
    }
}
