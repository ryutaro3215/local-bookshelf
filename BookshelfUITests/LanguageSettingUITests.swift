import XCTest

/// 言語（設定の「言語」: システムに合わせる・日本語・English。2026-11-19 オーナー指示）。
/// 選ぶとその場で（アプリを開き直さずに）画面の言語が変わり、設定の画面と見ていた棚はそのまま
@MainActor
final class LanguageSettingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element): \(predicate)")
    }

    /// 画面に出ている日本語（かな・漢字）の文字。選択肢「日本語」と iOS のスクロールバーの読み上げは除く
    private func japaneseTexts(_ app: XCUIApplication) throws -> [String] {
        var found: [String] = []
        var stack = [try app.snapshot()]
        while let node = stack.popLast() {
            stack.append(contentsOf: node.children)
            if node.elementType == .keyboard || node.identifier == "settings.language.ja" { continue }
            // スクロールバーの読み上げ（「垂直スクロールバー」）は iOS が端末の言語で付ける文言なので見ない
            if node.label.contains("スクロールバー") { continue }
            for text in [node.label, node.value as? String].compactMap({ $0 }) where Self.containsJapanese(text) {
                found.append("[\(node.identifier)] \(text)")
            }
        }
        return found
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChoosingALanguageSwitchesImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.japanese + ["-UITestReset", "-SeedBooks", "小説:3,エッセイ:2"]
        app.launch()
        let title = app.buttons["shelf.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        // 2つ目の棚（エッセイ）を見ている状態で設定を開く
        title.tap()
        XCTAssertTrue(app.buttons["picker.row.エッセイ"].waitForExistence(timeout: 5))
        app.buttons["picker.row.エッセイ"].tap()
        wait(title, "label == 'エッセイ'")
        app.buttons["browse.display"].tap()
        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 5))
        app.buttons["menu.settings"].tap()

        let system = app.buttons["settings.language.system"]
        let english = app.buttons["settings.language.en"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        XCTAssertTrue(system.isSelected, "初期値はシステムに合わせる")
        XCTAssertEqual(english.label, "English")

        // English を選ぶと、開き直さずに設定の画面が英語になる（設定は開いたまま）
        english.tap()
        let settingsTitle = element(app, "settings.title")
        wait(settingsTitle, "label == 'Settings'")
        XCTAssertTrue(app.buttons["settings.language.en"].isSelected)
        XCTAssertEqual(app.buttons["settings.appearance.system"].label, "Match System")
        XCTAssertEqual(app.buttons["settings.language.ja"].label, "日本語")
        XCTAssertEqual(try japaneseTexts(app), [])
        shot(app, "language_en_settings")

        // 戻ると、見ていた棚（Essays）のまま英語になっている
        app.buttons["settings.back"].tap()
        wait(app.buttons["shelf.title"], "label == 'Essays'")
        // 画面の部品（本の題名はユーザーのデータなので翻訳しない。見ない）
        for id in ["browse.add", "browse.display", "browse.search", "shelf.position", "shelf.share"] {
            let part = element(app, id)
            XCTAssertTrue(part.exists, id)
            XCTAssertFalse(Self.containsJapanese(part.label), "\(id): \(part.label)")
            XCTAssertFalse(Self.containsJapanese(part.value as? String ?? ""), "\(id): \(part.value ?? "")")
        }
        shot(app, "language_en_browse")

        // 日本語に戻す
        app.buttons["browse.display"].tap()
        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 5))
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(app.buttons["settings.language.ja"].waitForExistence(timeout: 5))
        app.buttons["settings.language.ja"].tap()
        wait(element(app, "settings.title"), "label == '設定'")
        app.buttons["settings.back"].tap()
        wait(app.buttons["shelf.title"], "label == 'エッセイ'")
    }
}
