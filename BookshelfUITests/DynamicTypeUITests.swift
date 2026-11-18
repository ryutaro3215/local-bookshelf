import XCTest

/// 最大の文字サイズ（Dynamic Type の最大＝アクセシビリティ XXXL）での主要画面の確認（plan T12。N5・N7・N-083）。
/// 日本語・英語それぞれで、閲覧・登録・詳細・編集・検索・設定・購入月別・チュートリアル・共有の主な操作ボタンが
/// 画面の中にあって押せること、編集画面の行が重ならず所持状況の切り替えが省略されない形（縦並び・幅いっぱい）になることを確かめる。
/// 各画面のスクリーンショットをテストの結果（xcresult）に残す。環境変数 BOOKSHELF_SHOTS_DIR があればそのフォルダにも書き出す
/// （xcodebuild には TEST_RUNNER_BOOKSHELF_SHOTS_DIR=… で渡す）。題名は DebugSeed の架空のもの、表紙は合成画像
@MainActor
final class DynamicTypeUITests: XCTestCase {
    private static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    private static let seed = "哲学・思想:3,小説:3@2026-10-05"
    private var prefix = "ja"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(_ language: [String], extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            language + Self.largest + ["-UITestReset", "-SeedBooks", Self.seed, "-FakeCamera", "blank"] + extra
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

    /// 画面の中にあって押せる（スクロールの中のものは、見えるまで上へ送る）
    private func assertReachable(
        _ app: XCUIApplication, _ identifier: String, scrollIn scroll: XCUIElement? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let target = element(app, identifier)
        // スクロールの中のものは、（まだ作られていなければ現れるまで）全体がスクロールの枠に入るまでゆっくり上へ送る
        if let scroll {
            XCTAssertTrue(
                scroll.waitForExistence(timeout: 10), "\(prefix): \(identifier) のスクロールが無い", file: file, line: line)
            for _ in 0..<10
            where !(target.exists && target.isHittable && scroll.frame.contains(target.frame.insetBy(dx: 1, dy: 1))) {
                scroll.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(prefix): \(identifier) が無い", file: file, line: line)
        let bounds = scroll?.frame ?? app.windows.firstMatch.frame
        XCTAssertTrue(target.isHittable, "\(prefix): \(identifier) が押せない", file: file, line: line)
        XCTAssertTrue(
            bounds.contains(target.frame.insetBy(dx: 1, dy: 1)),
            "\(prefix): \(identifier) が画面（スクロールの枠）の外にはみ出している: \(target.frame)", file: file, line: line)
    }

    /// スクリーンショットを結果に残す（BOOKSHELF_SHOTS_DIR があれば書き出す）
    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(prefix)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["BOOKSHELF_SHOTS_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(prefix)_ax5_\(name).png")
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    // MARK: - テスト

    func testLargestTextJapanese() {
        prefix = "ja"
        checkMainScreens(UITestLanguage.japanese)
    }

    func testLargestTextEnglish() {
        prefix = "en"
        checkMainScreens(UITestLanguage.english)
    }

    func testLargestTextOnboardingJapanese() {
        prefix = "ja"
        checkOnboarding(UITestLanguage.japanese)
    }

    func testLargestTextOnboardingEnglish() {
        prefix = "en"
        checkOnboarding(UITestLanguage.english)
    }

    // MARK: - 主要画面

    private func checkMainScreens(_ language: [String]) {
        var app = launch(language)

        // 閲覧（Q-1）: 下部バー（表示・検索・＋）と上の棚の名前・共有マークが画面の中で押せる（N-083）
        for id in ["shelf.title", "shelf.share", "browse.display", "browse.search", "browse.add"] {
            assertReachable(app, id)
        }
        shot(app, "Q-1_browse")

        // 表示メニュー: 項目を省略せず、入らなければスクロールで「設定」まで届く
        app.buttons["browse.display"].tap()
        let menu = element(app, "menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        assertReachable(app, "menu.mode.grid")
        assertReachable(app, "menu.group.month")
        shot(app, "G-2_menu")
        assertReachable(app, "menu.settings", scrollIn: menu)
        app.buttons["menu.settings"].tap()

        // 設定（F-1）→ ジャンル管理（F-2）
        assertReachable(app, "settings.genres")
        shot(app, "F-1_settings")
        app.buttons["settings.genres"].tap()
        assertReachable(app, "genres.add")
        assertReachable(app, "genres.edit")
        shot(app, "F-2_genres")

        // 詳細（Q-3）→ 編集（E-6）
        app.terminate()
        app = launch(language)
        element(app, "shelf.book.0").tap()
        assertReachable(app, "detail.back")
        assertReachable(app, "detail.edit")
        shot(app, "Q-3_detail")
        app.buttons["detail.edit"].tap()
        checkEditScreen(app)
        app.buttons["edit.cancel"].tap()
        assertReachable(app, "detail.back")
        app.buttons["detail.back"].tap()

        // 検索（E-4）
        assertReachable(app, "browse.search")
        app.buttons["browse.search"].tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        assertReachable(app, "search.field")
        assertReachable(app, "search.cancel")
        shot(app, "E-4_search")
        app.buttons["search.cancel"].tap()

        // 共有（K-2・K-4）
        assertReachable(app, "shelf.share")
        app.buttons["shelf.share"].tap()
        let destinations = element(app, "share.destinations")
        XCTAssertTrue(destinations.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "share.image").waitForExistence(timeout: 10))
        shot(app, "K-2_share")
        let ids = [
            "share.destination.feed", "share.destination.story", "share.destination.x", "share.destination.photos",
        ]
        for id in ids {
            assertReachable(app, id, scrollIn: destinations)
        }
        assertReachable(app, "share.cancel")
        app.buttons["share.destination.story"].tap()
        XCTAssertTrue(element(app, "share.preview").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "share.image").waitForExistence(timeout: 10))
        for id in ["share.back", "share.post", "share.save"] {
            assertReachable(app, id)
        }
        // 見出しと「‹ 戻る」が重ならない
        XCTAssertFalse(
            element(app, "share.preview.title").frame.intersects(app.buttons["share.back"].frame),
            "\(prefix): プレビューの見出しが「戻る」に重なっている")
        shot(app, "K-4_preview")
        app.buttons["share.back"].tap()
        XCTAssertTrue(destinations.waitForExistence(timeout: 5))
        app.buttons["share.cancel"].tap()
        wait(element(app, "share.sheet"), "exists == false")

        // 購入月別（J-1）と、範囲の選択（K-3）
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu").waitForExistence(timeout: 5))
        element(app, "menu.group.month").tap()
        XCTAssertTrue(element(app, "month.title").waitForExistence(timeout: 5))
        for id in ["month.title", "shelf.share", "browse.display", "browse.search", "browse.add"] {
            assertReachable(app, id)
        }
        shot(app, "J-1_month")
        app.buttons["shelf.share"].tap()
        let range = element(app, "share.range")
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        assertReachable(app, "share.range.day")
        assertReachable(app, "share.range.month")
        // 範囲の名前（この日／この月）と補足を省略しない: 2つの行のラベルが違い、名前が読める
        XCTAssertNotEqual(element(app, "share.range.day").label, element(app, "share.range.month").label)
        assertReachable(app, "share.next", scrollIn: range)
        assertReachable(app, "share.cancel", scrollIn: range)
        shot(app, "K-3_range")
        app.buttons["share.cancel"].tap()
        wait(element(app, "share.sheet"), "exists == false")

        // 登録（A-2 → A-3 → C-2）
        assertReachable(app, "browse.add")
        app.buttons["browse.add"].tap()
        XCTAssertTrue(app.buttons["register.camera"].waitForExistence(timeout: 5))
        assertReachable(app, "register.destination")
        assertReachable(app, "register.camera")
        shot(app, "A-2_register")
        // 最大の文字サイズではシートの中をスクロールして届く
        assertReachable(app, "register.library", scrollIn: app.scrollViews.firstMatch)
        assertReachable(app, "register.cancel", scrollIn: app.scrollViews.firstMatch)
        // シートを閉じないよう、シートの中のスクロールだけを戻す
        for _ in 0..<3 where !app.buttons["register.camera"].isHittable {
            app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        }
        app.buttons["register.camera"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        for id in ["capture.close", "capture.shutter", "capture.library"] {
            assertReachable(app, id)
        }
        shot(app, "A-3_capture")
        wait(shutter, "isEnabled == true")
        shutter.tap()
        wait(app.staticTexts["capture.count"], "label CONTAINS '1'", timeout: 20)
        assertReachable(app, "capture.done")
        app.buttons["capture.done"].tap()
        XCTAssertTrue(app.buttons["pending.register"].waitForExistence(timeout: 30))
        for id in ["pending.close", "pending.register", "pending.addCamera", "pending.addLibrary"] {
            assertReachable(app, id)
        }
        // 最大の文字サイズでは、本の行は追加ボタンの下にあり、一覧をスクロールして届く
        let list = app.collectionViews.firstMatch
        assertReachable(app, "pending.row.0.title", scrollIn: list)
        assertReachable(app, "pending.row.0.check", scrollIn: list)
        // 「閉じる」と見出しが重ならない
        XCTAssertFalse(
            app.buttons["pending.close"].frame.intersects(app.staticTexts["pending.heading"].frame),
            "\(prefix): 登録待ちの見出しが「閉じる」に重なっている")
        shot(app, "C-2_pending")
    }

    /// 編集（E-6）: 上の行のボタンと見出しが重ならない・カードの行が重ならない・所持状況の切り替えが縦並びで幅いっぱい
    private func checkEditScreen(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 5))
        assertReachable(app, "edit.cancel")
        assertReachable(app, "edit.done")
        let cancel = app.buttons["edit.cancel"].frame
        let done = app.buttons["edit.done"].frame
        XCTAssertFalse(cancel.intersects(done), "\(prefix): キャンセルと完了が重なっている")
        let heading = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["本を編集", "Edit Book"])).firstMatch
        XCTAssertTrue(heading.exists)
        XCTAssertFalse(heading.frame.intersects(cancel), "\(prefix): 見出しがキャンセルに重なっている")
        XCTAssertFalse(heading.frame.intersects(done), "\(prefix): 見出しが完了に重なっている")
        shot(app, "E-6_edit")

        // カードの行（ジャンル・所持状況・購入日）までスクロール
        let scroll = app.scrollViews.firstMatch
        assertReachable(app, "edit.purchaseDate", scrollIn: scroll)
        let genre = element(app, "edit.genre").frame
        let ownershipRow = element(app, "edit.ownershipRow").frame
        let date = element(app, "edit.purchaseDate").frame
        XCTAssertLessThanOrEqual(genre.maxY, ownershipRow.minY + 1, "\(prefix): ジャンルと所持状況の行が重なっている")
        XCTAssertLessThanOrEqual(ownershipRow.maxY, date.minY + 1, "\(prefix): 所持状況と購入日の行が重なっている")

        // 所持状況の切り替え: 2つを縦に並べ、それぞれ幅いっぱい（固定幅 76 で文言を省略しない）
        let owned = element(app, "edit.ownership.owned")
        let wanted = element(app, "edit.ownership.wanted")
        XCTAssertTrue(owned.isHittable)
        XCTAssertTrue(wanted.isHittable)
        XCTAssertLessThanOrEqual(owned.frame.maxY, wanted.frame.minY + 1, "\(prefix): 所持状況の切り替えが縦に並んでいない")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(owned.frame.width, window.width * 0.6, "\(prefix): 「購入済み」の幅が狭い: \(owned.frame)")
        XCTAssertGreaterThan(wanted.frame.width, window.width * 0.6, "\(prefix): 「買いたい」の幅が狭い: \(wanted.frame)")
        shot(app, "E-6_edit_rows")
        // 「買いたい」に切り替えても行が重ならない
        wanted.tap()
        XCTAssertTrue(element(app, "edit.purchaseDateDisabled").waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            element(app, "edit.ownershipRow").frame.maxY, element(app, "edit.purchaseDateDisabled").frame.minY + 1)
        shot(app, "E-6_edit_wanted")
        app.swipeDown()
        assertReachable(app, "edit.cancel")
    }

    // MARK: - チュートリアル（L-1・L-2・O-1）

    private func checkOnboarding(_ language: [String]) {
        let app = XCUIApplication()
        app.launchArguments =
            language + Self.largest + [
                "-UITestPersistentStore", "-UITestOnboarding", "-UITestCameraPermission", "-UITestReset",
                "-FakeCamera", "cover:PAPER COMETS",
            ]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        assertReachable(app, "onboarding.start")
        shot(app, "L-1_welcome")
        app.buttons["onboarding.start"].tap()
        let confirm = app.buttons["onboarding.shelf.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        assertReachable(app, "onboarding.shelf.confirm")
        // 棚の一覧（最大の文字サイズでは見出しも一緒にスクロールする）
        let list = app.scrollViews.firstMatch
        assertReachable(app, "onboarding.shelf.row.歴史", scrollIn: list)
        shot(app, "L-2_shelf")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["onboarding.permission.heading"].waitForExistence(timeout: 5))
        assertReachable(app, "onboarding.permission.allow")
        assertReachable(app, "onboarding.permission.library")
        shot(app, "O-1_permission")
    }
}
