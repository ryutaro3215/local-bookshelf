import XCTest

/// 起動時の言語・地域（N7）。シミュレータの言語設定に左右されないよう、UI テストは言語を指定して起動する
enum UITestLanguage {
    /// 既定（日本語）。既存の UI テストは日本語の文言・読み上げに依存するので、これを付けて起動する
    static let japanese = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    /// 英語（T15 の確認用）
    static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
}

/// 日英ローカライズ（plan T15。N7）。英語で起動し、閲覧・登録・詳細・設定・共有（共有ボタン。共有の画面は T11）の各画面に
/// 日本語が残っていないこと、日付が端末のロケール（en_US）の表記で出ること、初期ジャンル・システム棚・区分が英語名で出ることを確かめる。
/// 本の題名は架空の英語の題名（DebugSeed が英語表示のときに作る）。ユーザーが作った棚・題名は翻訳しない（N7）
@MainActor
final class LocalizationUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(seed: String, camera: String = "blank", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLanguage.english + ["-UITestReset", "-SeedBooks", seed, "-FakeCamera", camera] + extra
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

    /// 今日の日付（en_US の端末ロケールの表記。例「Nov 16, 2026」）
    private func todayInEnglish() -> String {
        Date().formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "en_US"))
        )
    }

    /// 日本語（ひらがな・カタカナ・漢字・和文の記号）を含むか
    nonisolated static func containsJapanese(_ text: String) -> Bool {
        text.range(of: "[\\p{Hiragana}\\p{Katakana}\\p{Han}・「」（）、。]", options: .regularExpression) != nil
    }

    /// 画面に出ている文字（ラベル・値・プレースホルダ）に日本語が無いことを確かめる。
    /// accessibilityIdentifier はデータ上の名前（日本語）を含むので見ない。キーボードはアプリの文言ではないので見ない
    private func assertNoJapanese(
        _ app: XCUIApplication, _ screen: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let snapshot: XCUIElementSnapshot
        do {
            snapshot = try app.snapshot()
        } catch {
            XCTFail("\(screen): 画面の要素を読めない（\(error)）", file: file, line: line)
            return
        }
        var found: [String] = []
        var stack: [XCUIElementSnapshot] = [snapshot]
        while let node = stack.popLast() {
            if node.elementType == .keyboard { continue }
            // 設定の言語の選択肢「日本語」は、どの言語で表示していても日本語で書く（言語名はその言語自身で書く）
            if node.identifier == "settings.language.ja" { continue }
            let texts = [node.label, node.value as? String, node.placeholderValue].compactMap { $0 }
            for text in texts where Self.containsJapanese(text) {
                found.append("[\(node.identifier)] \(text)")
            }
            stack.append(contentsOf: node.children)
        }
        XCTAssertTrue(found.isEmpty, "\(screen) に日本語が残っている: \(found)", file: file, line: line)
    }

    // MARK: - 閲覧・詳細・編集・検索

    /// 閲覧（棚・グリッド・表示メニュー・棚を選ぶ・長押しの選択・移動先・削除の確認）→ 詳細 → 編集 → 検索
    func testBrowseDetailEditAndSearchAreInEnglish() {
        let app = launch(seed: "哲学・思想:3,小説:2+1")
        let title = app.buttons["shelf.title"]
        // 初期ジャンルは英語名（Q-1）。冊数は複数形
        XCTAssertTrue(["Philosophy", "Fiction"].contains(title.label), title.label)
        if title.label != "Philosophy" {
            title.tap()
            app.buttons["picker.row.哲学・思想"].tap()
        }
        wait(title, "label == 'Philosophy'")
        XCTAssertEqual(title.value as? String, "3 books")
        // 日付は端末のロケールの表記（Q-1「Purchased Oct 20, 2026」）
        XCTAssertEqual(element(app, "shelf.bookMeta").label, "Purchased \(todayInEnglish())")
        XCTAssertEqual(app.buttons["browse.search"].label, "Search title or reading")
        XCTAssertEqual(app.buttons["shelf.share"].label, "Share")
        assertNoJapanese(app, "閲覧（棚）")

        // 棚を選ぶ（区分の見出しも英語）
        title.tap()
        XCTAssertTrue(app.buttons["picker.row.小説"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["picker.row.小説"].label, "Fiction")
        XCTAssertEqual(element(app, "picker.category.人文").label, "Humanities")
        XCTAssertEqual(app.buttons["picker.row.買いたい本"].label, "Wishlist")
        assertNoJapanese(app, "棚を選ぶ")
        app.buttons["picker.row.哲学・思想"].tap()
        wait(title, "label == 'Philosophy'")

        // 表示メニュー（並べ順を含む）→ グリッド
        app.buttons["browse.display"].tap()
        XCTAssertTrue(app.buttons["menu.mode.grid"].waitForExistence(timeout: 5))
        assertNoJapanese(app, "表示メニュー")
        app.buttons["menu.mode.grid"].tap()
        XCTAssertTrue(element(app, "grid.book.0").waitForExistence(timeout: 5))
        assertNoJapanese(app, "グリッド")
        // グリッドの長押しメニュー（I-2）
        element(app, "grid.book.0").press(forDuration: 1.0)
        XCTAssertTrue(element(app, "gridMenu").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "gridMenu.detail").label, "View Details")
        assertNoJapanese(app, "グリッドの長押しメニュー")
        element(app, "gridMenu.dismiss").tap()
        wait(element(app, "gridMenu"), "exists == false")
        app.buttons["browse.display"].tap()
        app.buttons["menu.mode.shelf"].tap()
        XCTAssertTrue(app.collectionViews["shelf.carousel"].waitForExistence(timeout: 5))

        // 長押しで選ぶ（D-1）→ 移動先の棚（D-2）→ キャンセル → 削除の確認（H-2）→ キャンセル
        let carousel = app.collectionViews["shelf.carousel"]
        carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0)
        XCTAssertTrue(element(app, "select.state").waitForExistence(timeout: 5))
        assertNoJapanese(app, "本を選択")
        app.buttons["select.move"].tap()
        XCTAssertTrue(element(app, "move.title").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["move.row.小説"].label, "Fiction")
        assertNoJapanese(app, "移動先の棚")
        app.buttons["move.cancel"].tap()
        wait(element(app, "move.title"), "exists == false")
        if !element(app, "select.state").exists {
            carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0)
            XCTAssertTrue(element(app, "select.state").waitForExistence(timeout: 5))
        }
        app.buttons["select.delete"].tap()
        XCTAssertTrue(element(app, "delete.dialog").waitForExistence(timeout: 5))
        assertNoJapanese(app, "削除の確認")
        app.buttons["delete.cancel"].tap()
        wait(element(app, "delete.dialog"), "exists == false")
        if element(app, "select.state").exists {
            element(app, "shelf.bookTitle").tap()
            wait(element(app, "select.state"), "exists == false")
        }

        // 詳細（Q-2: Genre / Ownership / Purchase Date）
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.edit"].label, "Edit")
        XCTAssertEqual(app.buttons["detail.back"].label, "Back to Philosophy")
        let genre = element(app, "detail.genre").label
        XCTAssertTrue(genre.contains("Genre") && genre.contains("Philosophy"), genre)
        let ownership = element(app, "detail.ownership").label
        XCTAssertTrue(ownership.contains("Ownership") && ownership.contains("Owned"), ownership)
        let date = element(app, "detail.purchaseDate").label
        XCTAssertTrue(date.contains("Purchase Date") && date.contains(todayInEnglish()), date)
        assertNoJapanese(app, "詳細")

        // 編集（E-6）。所持状況を「Wishlist」に切り替えた状態も見る。キャンセルで何も保存しない
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "edit.purchaseDate").value as? String, todayInEnglish())
        assertNoJapanese(app, "編集（購入済み）")
        app.buttons["edit.ownership.wanted"].tap()
        XCTAssertTrue(element(app, "edit.purchaseDateDisabled").waitForExistence(timeout: 5))
        assertNoJapanese(app, "編集（買いたい）")
        app.buttons["edit.genre"].tap()
        XCTAssertTrue(app.buttons["edit.genre.row.小説"].waitForExistence(timeout: 5))
        assertNoJapanese(app, "ジャンルを選ぶ")
        app.buttons["edit.genre.row.哲学・思想"].tap()
        app.buttons["edit.cancel"].tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))

        // 買いたい本の棚（M-1）と、その本の詳細（E-2）
        title.tap()
        app.buttons["picker.row.買いたい本"].tap()
        wait(title, "label == 'Wishlist'")
        assertNoJapanese(app, "買いたい本の棚")
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(app.buttons["detail.purchase"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.purchase"].label, "Mark as Purchased")
        assertNoJapanese(app, "詳細（買いたい本）")
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))

        // 検索（E-4・E-5）
        app.buttons["browse.search"].tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("The")
        XCTAssertTrue(element(app, "search.result.0").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "search.count").label.hasSuffix("results (title or reading match)"))
        assertNoJapanese(app, "検索結果")
        field.typeText("zzz")
        XCTAssertTrue(element(app, "search.empty.title").waitForExistence(timeout: 5))
        assertNoJapanese(app, "検索0件")
    }

    // MARK: - 登録

    /// 登録方法のシート（A-2）→ 撮影画面（A-3）→ 登録待ち（C）→ 題名の編集（C-3）→ 閉じるときの確認
    func testRegistrationFlowIsInEnglish() {
        let app = launch(seed: "小説:1", camera: "blank")
        app.buttons["browse.add"].tap()
        XCTAssertTrue(app.buttons["register.camera"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "Unsorted")
        assertNoJapanese(app, "登録方法のシート")
        app.buttons["register.camera"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        assertNoJapanese(app, "撮影画面")
        wait(shutter, "isEnabled == true")
        shutter.tap()
        wait(app.staticTexts["capture.count"], "label CONTAINS '1 / 30'", timeout: 20)
        assertNoJapanese(app, "撮影画面（1冊）")
        app.buttons["capture.done"].tap()
        XCTAssertTrue(app.textFields["pending.row.0.title"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["pending.heading"].label, "Pending 1 / 30")
        XCTAssertTrue(element(app, "pending.untitledNotice").waitForExistence(timeout: 60))
        XCTAssertEqual(app.buttons["pending.register"].label, "Enter titles to add")
        assertNoJapanese(app, "登録待ち")
        app.buttons["pending.fillNext"].tap()
        XCTAssertTrue(element(app, "titleEditor.remaining").waitForExistence(timeout: 5))
        assertNoJapanese(app, "題名の編集")
        app.buttons["titleEditor.back"].tap()
        XCTAssertTrue(app.buttons["pending.close"].waitForExistence(timeout: 5))
        app.buttons["pending.close"].tap()
        let discard = app.buttons["Close Without Adding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        assertNoJapanese(app, "閉じるときの確認")
        discard.tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))
    }

    // MARK: - 設定

    /// 設定（F-1）→ ジャンル管理（F-2・F-4）→ 追加（F-3）→ 名前の変更（F-4b）・削除の確認（F-5）→ ライセンス
    func testSettingsAndGenreManagementAreInEnglish() {
        let app = launch(seed: "小説:2")
        app.buttons["browse.display"].tap()
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(app.buttons["settings.genres"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.genres"].label, "Manage Genres")
        assertNoJapanese(app, "設定")

        app.buttons["settings.genres"].tap()
        XCTAssertTrue(app.buttons["genres.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "genres.category.文芸").label, "Literature")
        XCTAssertEqual(element(app, "genre.row.小説").label, "Fiction")
        XCTAssertEqual(element(app, "genre.row.小説").value as? String, "2 books")
        XCTAssertEqual(element(app, "genre.row.エッセイ").value as? String, "0 books, Hidden")
        assertNoJapanese(app, "ジャンル管理")
        // 末尾（区分「その他」・システム棚・注記）
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(element(app, "genres.footnote").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "genres.category.その他").label, "Other")
        XCTAssertEqual(element(app, "genre.row.未分類").label, "Unsorted")
        assertNoJapanese(app, "ジャンル管理（末尾）")
        app.swipeDown()
        app.swipeDown()

        // 追加（F-3）
        app.buttons["genres.add"].tap()
        XCTAssertTrue(element(app, "genreAdd.title").waitForExistence(timeout: 5))
        assertNoJapanese(app, "ジャンルの追加")
        app.buttons["genreAdd.cancel"].tap()

        // 編集モード → 名前の変更 → キャンセル → 削除の確認 → キャンセル
        app.buttons["genres.edit"].tap()
        XCTAssertTrue(app.buttons["genre.rename.小説"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["genre.rename.小説"].label, "Rename Fiction")
        assertNoJapanese(app, "ジャンル管理（編集モード）")
        app.buttons["genre.rename.小説"].tap()
        XCTAssertTrue(element(app, "rename.dialog").waitForExistence(timeout: 5))
        // 名前の欄の初期値は画面に出ている名前（英語名）
        XCTAssertEqual(app.textFields["rename.field"].value as? String, "Fiction")
        assertNoJapanese(app, "名前の変更")
        app.buttons["rename.cancel"].tap()
        app.buttons["genre.delete.小説"].tap()
        XCTAssertTrue(element(app, "genreDelete.dialog").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "genreDelete.title").label, "Delete “Fiction”?")
        assertNoJapanese(app, "ジャンルの削除の確認")
        app.buttons["genreDelete.cancel"].tap()
        app.buttons["genres.edit"].tap()

        // ライセンス
        app.buttons["genres.back"].tap()
        XCTAssertTrue(app.buttons["settings.license"].waitForExistence(timeout: 5))
        app.buttons["settings.license"].tap()
        XCTAssertTrue(element(app, "license.title").waitForExistence(timeout: 5))
        assertNoJapanese(app, "ライセンス")
    }

    // MARK: - 購入月別（T13）

    /// 購入月別（J-1）の月の名前・冊数・本の情報、年にまとめた表示（J-2）の月の並び、表示メニューが英語
    func testMonthModeIsInEnglish() {
        let app = launch(seed: "小説:3@2026-10-05,哲学・思想:2@2026-11-02")
        app.buttons["browse.display"].tap()
        element(app, "menu.group.month").tap()
        let title = element(app, "month.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // 月・年の見出しは端末のロケール（en_US）の書式
        wait(title, "label == 'November 2026'")
        XCTAssertEqual(title.value as? String, "2 books")
        XCTAssertEqual(element(app, "shelf.bookMeta").label, "Philosophy · Purchased Nov 2, 2026")
        assertNoJapanese(app, "購入月別（月）")
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu.group.month").waitForExistence(timeout: 5))
        assertNoJapanese(app, "表示メニュー（購入月別）")
        element(app, "menu.dismiss").tap()

        // 購入月別のグリッド → 長押しメニュー → 詳細。戻る先の名前も英語の書式（「November 2026」）
        app.buttons["browse.display"].tap()
        element(app, "menu.mode.grid").tap()
        XCTAssertTrue(element(app, "grid.book.0").waitForExistence(timeout: 5))
        assertNoJapanese(app, "購入月別のグリッド")
        wait(element(app, "grid.book.0"), "hittable == true")
        element(app, "grid.book.0").press(forDuration: 1.5)
        XCTAssertTrue(element(app, "gridMenu").waitForExistence(timeout: 5))
        assertNoJapanese(app, "購入月別のグリッドの長押しメニュー")
        element(app, "gridMenu.detail").tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.back"].label, "Back to November 2026")
        assertNoJapanese(app, "購入月別のグリッドから開いた詳細")
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["browse.display"].waitForExistence(timeout: 5))
        app.buttons["browse.display"].tap()
        element(app, "menu.mode.shelf").tap()

        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        carousel.pinch(withScale: 0.4, velocity: -1)
        wait(title, "label == '2026'")
        XCTAssertEqual(title.value as? String, "5 books")
        XCTAssertEqual(element(app, "month.tab.10").label, "Oct")
        XCTAssertEqual(element(app, "month.tab.11").label, "Nov")
        assertNoJapanese(app, "購入月別（年）")

    }

    // MARK: - 初回チュートリアル（T14）

    /// ようこそ（L-1）→ 最初の棚（L-2）→ カメラの許可（O-1）→ 案内つきの撮影（L-3）→ 最初の1冊（L-4）
    func testOnboardingIsInEnglish() {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLanguage.english + [
                "-UITestPersistentStore", "-UITestOnboarding", "-UITestCameraPermission", "-UITestReset",
                "-FakeCamera", "cover:PAPER COMETS",
            ]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        assertNoJapanese(app, "ようこそ")
        app.buttons["onboarding.start"].tap()
        let confirm = app.buttons["onboarding.shelf.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Take Photos for Unsorted")
        XCTAssertEqual(app.buttons["onboarding.shelf.row.歴史"].label, "History")
        assertNoJapanese(app, "最初の棚")
        app.buttons["onboarding.shelf.row.歴史"].tap()
        wait(confirm, "label == 'Take Photos for History'")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["onboarding.permission.heading"].waitForExistence(timeout: 5))
        assertNoJapanese(app, "カメラの許可")
        app.buttons["onboarding.permission.allow"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["capture.shutterHint"].exists)
        assertNoJapanese(app, "案内つきの撮影")
        wait(shutter, "isEnabled == true")
        shutter.tap()
        let field = app.textFields["pending.row.0.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        wait(app.staticTexts["Reading the title…"], "exists == false", timeout: 90)
        let value = field.value as? String ?? ""
        if value.isEmpty || value == "Enter title" {
            field.tap()
            field.typeText("Fictional Book")
            app.staticTexts["pending.heading"].tap()
        }
        let register = app.buttons["pending.register"]
        wait(register, "isEnabled == true")
        register.tap()
        XCTAssertTrue(app.staticTexts["firstBook.heading"].waitForExistence(timeout: 10))
        assertNoJapanese(app, "最初の1冊")
        app.buttons["firstBook.browse"].tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["shelf.title"].label, "History")
    }

    // MARK: - 最大の文字サイズ

    /// 英語・最大の文字サイズ（Dynamic Type の AX5）で、詳細のカードが縦並び（Q-3）になり画面の中に収まる。
    /// 閲覧画面は AX5 で下部バーが画面の外に押し出される（日本語でも同じ。T15 以前から。docs/notices.md に記録）ため、ここでは見ない
    func testLargestTextSizeKeepsDetailOnScreen() {
        let app = launch(
            seed: "哲学・思想:2",
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let window = app.windows.firstMatch.frame
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        // 項目名を値の上に置く縦並び（Q-3）。カードの1行目は画面の中に収まり、横並びの1行（高さ 52）より高い
        let genre = element(app, "detail.genre").frame
        XCTAssertTrue(window.contains(genre), "detail.genre が画面からはみ出している: \(genre)")
        XCTAssertGreaterThan(genre.height, 80)
        XCTAssertLessThanOrEqual(genre.width, window.width)
        assertNoJapanese(app, "詳細（最大の文字サイズ）")
    }
}
