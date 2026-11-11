import XCTest

/// ジャンルの管理の UI テスト（plan T8 の acceptance）。
/// 「表示」メニュー →「設定」→ ジャンル管理で、区分を選んで作成 → 名前の変更 → 並び替え → 削除し、
/// 削除したジャンルの本が未分類に出ること、買いたい本・未分類に削除・名前の変更の操作が出ないことを確かめる。
/// 起動引数 `-UITestReset` でまっさらなデータから始め、`-SeedBooks` で架空の本を入れる。ジャンル名も架空のもの
@MainActor
final class ShelfManagementUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-SeedBooks", seed]
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element): \(predicate)")
    }

    /// 閲覧画面 →「表示」→「設定」→「ジャンル管理」
    private func openGenres(_ app: XCUIApplication) {
        app.buttons["browse.display"].tap()
        element(app, "menu.settings").tap()
        XCTAssertTrue(element(app, "settings.title").waitForExistence(timeout: 5))
        element(app, "settings.genres").tap()
        XCTAssertTrue(element(app, "genres.title").waitForExistence(timeout: 5))
    }

    /// ジャンル管理 → 設定 → 閲覧画面
    private func backToBrowse(_ app: XCUIApplication) {
        element(app, "genres.back").tap()
        XCTAssertTrue(element(app, "settings.back").waitForExistence(timeout: 5))
        element(app, "settings.back").tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))
    }

    /// 要素が画面に見えるまで一覧を送る
    private func scrollTo(_ app: XCUIApplication, _ target: XCUIElement, up: Bool = false) {
        for _ in 0..<8 where !target.isHittable {
            if up {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(target.isHittable, "\(target) が画面に出ない")
    }

    // MARK: - acceptance

    /// 区分を選んで作成 → 名前の変更 → 並び替え → 本を入れて削除 → 本が未分類に出る
    func testCreateRenameReorderDeleteGenre() {
        let app = launch(seed: "小説:2")
        let firstTitle = element(app, "shelf.bookTitle").label
        openGenres(app)
        XCTAssertFalse(element(app, "genre.row.灯台守の書架").exists)

        // 作成（区分「人文」）。人文の末尾（言語・語学の次）に入る
        element(app, "genres.add").tap()
        XCTAssertTrue(element(app, "genreAdd.title").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "genreAdd.category.my").isSelected)
        XCTAssertFalse(element(app, "genreAdd.save").isEnabled)
        element(app, "genreAdd.name").typeText("灯台守の書架")
        XCTAssertEqual(element(app, "genreAdd.counter").label, "6/20")
        element(app, "genreAdd.category.humanities").tap()
        XCTAssertTrue(element(app, "genreAdd.category.humanities").isSelected)
        element(app, "genreAdd.save").tap()
        let created = element(app, "genre.row.灯台守の書架")
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(created.frame.minY, element(app, "genre.row.言語・語学").frame.minY)
        XCTAssertLessThan(created.frame.minY, element(app, "genre.row.政治・法律").frame.minY)
        XCTAssertEqual(created.value as? String, "0冊、本棚に非表示")

        // 編集モード: 買いたい本・未分類には削除・名前の変更・並び替えが出ない
        element(app, "genres.edit").tap()
        wait(element(app, "genres.edit"), "label == '完了'")
        XCTAssertFalse(element(app, "genres.back").exists)
        XCTAssertFalse(element(app, "genres.add").isEnabled)
        for name in ["買いたい本", "未分類"] {
            XCTAssertTrue(element(app, "genre.row.\(name)").exists, name)
            XCTAssertFalse(element(app, "genre.delete.\(name)").exists, name)
            XCTAssertFalse(element(app, "genre.rename.\(name)").exists, name)
            XCTAssertFalse(element(app, "genre.handle.\(name)").exists, name)
        }
        XCTAssertTrue(element(app, "genre.delete.小説").exists)

        // 名前の変更（F-4b）
        let rename = element(app, "genre.rename.灯台守の書架")
        scrollTo(app, rename)
        rename.tap()
        let field = element(app, "rename.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "rename.title").label, "ジャンル名を変更")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "夜更けの書架")
        element(app, "rename.save").tap()
        wait(element(app, "rename.dialog"), "exists == false")
        XCTAssertTrue(element(app, "genre.row.夜更けの書架").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "genre.row.灯台守の書架").exists)

        // 並び替え: ≡ を2行上（心理の位置）へドラッグ → 歴史と心理の間に入る
        let handle = element(app, "genre.handle.夜更けの書架")
        scrollTo(app, handle)
        let target = element(app, "genre.handle.心理")
        XCTAssertTrue(target.isHittable)
        handle.press(forDuration: 0.3, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        let moved = element(app, "genre.row.夜更けの書架")
        XCTAssertLessThan(moved.frame.minY, element(app, "genre.row.心理").frame.minY)
        XCTAssertGreaterThan(moved.frame.minY, element(app, "genre.row.歴史").frame.minY)
        XCTAssertLessThan(element(app, "genre.row.言語・語学").frame.minY, element(app, "genre.row.政治・法律").frame.minY)
        element(app, "genres.edit").tap()
        wait(element(app, "genres.edit"), "label == '編集'")

        // 閲覧画面で、小説の本を新しいジャンルへ移す（T7 の長押し＋上スワイプ）
        backToBrowse(app)
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        let start = carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)), withVelocity: .slow,
            thenHoldForDuration: 0.3)
        let row = element(app, "move.row.夜更けの書架")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "0冊")
        row.tap()
        element(app, "move.confirm").tap()
        wait(app.buttons["shelf.title"], "label == '夜更けの書架'")
        XCTAssertEqual(element(app, "shelf.bookTitle").label, firstTitle)

        // 削除（F-5）。中の本は未分類へ移る
        openGenres(app)
        XCTAssertEqual(element(app, "genre.row.夜更けの書架").value as? String, "1冊")
        element(app, "genres.edit").tap()
        let delete = element(app, "genre.delete.夜更けの書架")
        scrollTo(app, delete)
        delete.tap()
        XCTAssertTrue(element(app, "genreDelete.dialog").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "genreDelete.title").label, "「夜更けの書架」を削除しますか？")
        XCTAssertEqual(element(app, "genreDelete.message").label, "中の1冊は未分類に移動します。\n本は削除されません。")
        element(app, "genreDelete.confirm").tap()
        wait(element(app, "genre.row.夜更けの書架"), "exists == false")
        element(app, "genres.edit").tap()
        wait(element(app, "genres.edit"), "label == '編集'")
        XCTAssertEqual(element(app, "genre.row.未分類").value as? String, "1冊、変更できません")
        backToBrowse(app)

        // 表示していた棚が消えたので、本が移った未分類を見せる
        wait(app.buttons["shelf.title"], "label == '未分類'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
        XCTAssertEqual(element(app, "shelf.bookTitle").label, firstTitle)
        app.buttons["shelf.title"].tap()
        XCTAssertEqual(app.buttons["picker.row.未分類"].value as? String, "1冊")
        XCTAssertFalse(app.buttons["picker.row.夜更けの書架"].exists)
    }

    /// 編集モードでなくても、買いたい本・未分類には操作が出ない。設定の件数・追加のキャンセル・名前の上限
    func testSettingsAndSystemShelvesAreProtected() {
        let app = launch(seed: "小説:1+1")
        app.buttons["browse.display"].tap()
        element(app, "menu.settings").tap()
        XCTAssertTrue(element(app, "settings.title").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "settings.genres").value as? String, "28件")
        XCTAssertTrue(element(app, "settings.privacy").exists)
        element(app, "settings.genres").tap()
        XCTAssertTrue(element(app, "genres.title").waitForExistence(timeout: 5))

        // 区分の見出しと「その他」（システム）、冊数・非表示のタグ
        XCTAssertTrue(element(app, "genres.category.文芸").exists)
        XCTAssertTrue(element(app, "genres.category.その他").exists)
        XCTAssertFalse(element(app, "genres.category.マイジャンル").exists)
        XCTAssertEqual(element(app, "genre.row.小説").value as? String, "1冊")
        XCTAssertEqual(element(app, "genre.row.買いたい本").value as? String, "1冊、変更できません")
        XCTAssertEqual(element(app, "genre.row.エッセイ").value as? String, "0冊、本棚に非表示")
        for name in ["買いたい本", "未分類"] {
            XCTAssertFalse(element(app, "genre.delete.\(name)").exists, name)
            XCTAssertFalse(element(app, "genre.rename.\(name)").exists, name)
        }

        // 追加: 20文字まで。キャンセルでは増えない
        element(app, "genres.add").tap()
        let name = element(app, "genreAdd.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText(String(repeating: "灯", count: 25))
        XCTAssertEqual(element(app, "genreAdd.counter").label, "20/20")
        XCTAssertEqual(name.value as? String, String(repeating: "灯", count: 20))
        element(app, "genreAdd.cancel").tap()
        wait(element(app, "genreAdd.title"), "exists == false")
        element(app, "genres.back").tap()
        XCTAssertEqual(element(app, "settings.genres").value as? String, "28件")
    }
}
