import XCTest

/// 共有の流れの UI テスト（plan T11 の acceptance。F8・K-1〜K-5）。
/// 共有マーク →（購入月別では範囲の選択）→ 共有先の選択 → プレビューまで進めること、写真への保存で「追加のみ」の権限を求めることを確かめる。
/// 題名は DebugSeed の架空のもの、表紙は合成画像
@MainActor
final class ShareFlowUITests: XCTestCase {
    /// 哲学・思想に購入済み9冊・買いたい2冊（買いたいの本は共有しない）
    private let genreSeed = "哲学・思想:9+2"
    /// 2026年11月: 哲学・思想 2冊（11/02・11/03）／2026年10月: 小説 3冊（10/05〜10/07）
    private let monthSeed = "小説:3@2026-10-05,哲学・思想:2@2026-11-02"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.japanese + ["-UITestReset", "-SeedBooks", seed]
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

    /// 「表示」→「購入月別」
    private func switchToMonth(_ app: XCUIApplication) {
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu").waitForExistence(timeout: 5))
        element(app, "menu.group.month").tap()
        XCTAssertTrue(element(app, "month.title").waitForExistence(timeout: 5))
    }

    /// 共有先のシート（K-2）で、縮小の画像ができあがるまで待つ
    private func waitForDestinations(_ app: XCUIApplication, title: String) {
        XCTAssertTrue(element(app, "share.destinations").waitForExistence(timeout: 5))
        wait(element(app, "share.title"), "label == '\(title)'")
        XCTAssertTrue(element(app, "share.image").waitForExistence(timeout: 10), "共有画像の縮小が出ない")
    }

    /// 共有先を押してプレビュー（K-4・K-5）へ。画像ができあがるまで待つ
    private func openPreview(_ app: XCUIApplication, _ destination: String, title: String) {
        element(app, "share.destination.\(destination)").tap()
        XCTAssertTrue(element(app, "share.preview").waitForExistence(timeout: 5))
        wait(element(app, "share.preview.title"), "label == '\(title)'")
        XCTAssertTrue(element(app, "share.image").waitForExistence(timeout: 10), "プレビューの画像が出ない")
        wait(app.buttons["share.save"], "isEnabled == true")
    }

    // MARK: - ジャンル別（K-1 → K-2 → K-4・K-5）

    /// 共有マーク → 共有先（この棚を共有・購入済みの本だけ）→ X（4:5）・ストーリーズ（9:16）のプレビュー → キャンセルで閉じる
    func testGenreShareFlowReachesPreview() {
        let app = launch(seed: genreSeed)
        XCTAssertEqual(app.buttons["shelf.title"].label, "哲学・思想")
        app.buttons["shelf.share"].tap()

        // 範囲の選択は出ずに、共有先のシート（K-2）
        waitForDestinations(app, title: "この棚を共有")
        XCTAssertFalse(element(app, "share.range").exists)
        // 買いたい本の2冊は数えない
        XCTAssertEqual(element(app, "share.summary").label, "哲学・思想・9冊（購入済みの本だけ）")
        for destination in ["feed", "story", "x", "photos"] {
            XCTAssertTrue(element(app, "share.destination.\(destination)").exists, destination)
        }
        XCTAssertTrue(element(app, "share.destination.story").label.contains("9:16"))
        XCTAssertTrue(element(app, "share.destination.x").label.contains("4:5"))

        // X のポスト（4:5）
        openPreview(app, "x", title: "X のポスト（4:5）")
        XCTAssertEqual(app.buttons["share.post"].label, "X に投稿")
        XCTAssertTrue(app.buttons["share.save"].exists)
        XCTAssertTrue(app.staticTexts["フィード・X・保存は 4:5（1080×1350）"].exists)
        // 戻ってストーリーズ（9:16）
        app.buttons["share.back"].tap()
        waitForDestinations(app, title: "この棚を共有")
        openPreview(app, "story", title: "ストーリーズ（9:16）")
        XCTAssertEqual(app.buttons["share.post"].label, "ストーリーズに投稿")
        XCTAssertTrue(app.staticTexts["上 14%：ストーリーズの表示と重なる"].exists)
        XCTAssertTrue(app.staticTexts["下 20%：返信欄と重なる"].exists)

        // キャンセルで閉じて閲覧画面に戻る
        app.buttons["share.back"].tap()
        waitForDestinations(app, title: "この棚を共有")
        app.buttons["share.cancel"].tap()
        wait(element(app, "share.sheet"), "exists == false")
        XCTAssertTrue(app.buttons["shelf.title"].isHittable)
    }

    /// 買いたい本の棚には共有マークを出さない（共有画像に「買いたい」の本を含めないため）
    func testWishlistHasNoShareButton() {
        let app = launch(seed: genreSeed)
        app.buttons["shelf.title"].tap()
        let wishlist = element(app, "picker.row.買いたい本")
        XCTAssertTrue(wishlist.waitForExistence(timeout: 5))
        wishlist.tap()
        wait(app.buttons["shelf.title"], "label == '買いたい本'")
        XCTAssertFalse(app.buttons["shelf.share"].exists)
    }

    // MARK: - 購入月別（K-3 範囲を選ぶ）

    /// 購入月別: 共有マーク → 範囲（この日／この月）→ 次へ → この月を共有 → フィード（4:5）のプレビュー
    func testMonthShareChoosesRangeThenPreview() {
        let app = launch(seed: monthSeed)
        switchToMonth(app)
        wait(element(app, "month.title"), "label == '2026年11月'")
        app.buttons["shelf.share"].tap()

        // K-3: 見ている本（11/02 の1冊目）の日と、この月
        XCTAssertTrue(element(app, "share.range").waitForExistence(timeout: 5))
        let day = element(app, "share.range.day")
        let month = element(app, "share.range.month")
        XCTAssertTrue(day.label.contains("この日"), day.label)
        XCTAssertTrue(day.label.contains("11月2日・1冊"), day.label)
        XCTAssertTrue(month.label.contains("この月"), month.label)
        XCTAssertTrue(month.label.contains("2026年11月・2冊"), month.label)
        XCTAssertFalse(element(app, "share.range.year").exists)
        XCTAssertTrue(day.isSelected)
        month.tap()
        wait(month, "isSelected == true")
        XCTAssertFalse(day.isSelected)
        app.buttons["share.next"].tap()

        waitForDestinations(app, title: "この月を共有")
        XCTAssertEqual(element(app, "share.summary").label, "2026年11月・2冊（購入済みの本だけ）")
        openPreview(app, "feed", title: "フィード（4:5）")
        XCTAssertEqual(app.buttons["share.post"].label, "フィードに投稿")
    }

    /// 年にまとめると、範囲は「この日／この年」
    func testYearShareOffersDayAndYear() {
        let app = launch(seed: monthSeed)
        switchToMonth(app)
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        carousel.pinch(withScale: 0.4, velocity: -1)
        wait(element(app, "month.title"), "label == '2026年'")
        app.buttons["shelf.share"].tap()

        XCTAssertTrue(element(app, "share.range").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "share.range.day").exists)
        let year = element(app, "share.range.year")
        XCTAssertTrue(year.label.contains("2026年・5冊"), year.label)
        XCTAssertFalse(element(app, "share.range.month").exists)
        year.tap()
        app.buttons["share.next"].tap()
        waitForDestinations(app, title: "この年を共有")
        openPreview(app, "story", title: "ストーリーズ（9:16）")
    }

    /// 購入月別のグリッドでも、共有マークからいちばん上の月を共有できる（見ている本が無いので範囲の選択は出ない）
    func testMonthGridSharesTopMonth() {
        let app = launch(seed: monthSeed)
        switchToMonth(app)
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu").waitForExistence(timeout: 5))
        element(app, "menu.mode.grid").tap()
        XCTAssertTrue(element(app, "monthGrid").waitForExistence(timeout: 5))
        app.buttons["shelf.share"].tap()
        waitForDestinations(app, title: "この月を共有")
        XCTAssertFalse(element(app, "share.range").exists)
        XCTAssertEqual(element(app, "share.summary").label, "2026年11月・2冊（購入済みの本だけ）")
    }

    // MARK: - 英語表示（T15 の決まり）

    /// 英語で起動すると、共有の画面（範囲・共有先・プレビュー）に日本語が残らない。冊数は複数形
    func testShareScreensAreInEnglish() {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.english + ["-UITestReset", "-SeedBooks", monthSeed]
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        app.buttons["shelf.share"].tap()
        waitForDestinations(app, title: "Share This Shelf")
        XCTAssertTrue(
            element(app, "share.summary").label.hasSuffix("books (owned only)"), element(app, "share.summary").label)
        assertNoJapanese(app, "共有先（ジャンル別）")
        openPreview(app, "story", title: "Stories (9:16)")
        XCTAssertEqual(app.buttons["share.post"].label, "Post to Stories")
        XCTAssertTrue(app.staticTexts["Top 14%: covered by Stories controls"].exists)
        assertNoJapanese(app, "プレビュー（ストーリーズ）")
        app.buttons["share.back"].tap()
        waitForDestinations(app, title: "Share This Shelf")
        app.buttons["share.cancel"].tap()
        wait(element(app, "share.sheet"), "exists == false")

        // 購入月別の範囲の選択
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu").waitForExistence(timeout: 5))
        element(app, "menu.group.month").tap()
        XCTAssertTrue(element(app, "month.title").waitForExistence(timeout: 5))
        app.buttons["shelf.share"].tap()
        XCTAssertTrue(element(app, "share.range").waitForExistence(timeout: 5))
        let month = element(app, "share.range.month")
        XCTAssertTrue(month.label.contains("This Month"), month.label)
        XCTAssertTrue(month.label.contains("2 books"), month.label)
        XCTAssertTrue(element(app, "share.range.day").label.contains("1 book"), element(app, "share.range.day").label)
        assertNoJapanese(app, "範囲の選択")
    }

    /// 画面に出ている文字（ラベル・値・プレースホルダ）に日本語が無いことを確かめる（識別子は見ない）
    private func assertNoJapanese(_ app: XCUIApplication, _ screen: String, line: UInt = #line) {
        guard let snapshot = try? app.snapshot() else {
            XCTFail("\(screen): 画面の要素を読めない", line: line)
            return
        }
        var found: [String] = []
        var stack: [XCUIElementSnapshot] = [snapshot]
        while let node = stack.popLast() {
            let texts = [node.label, node.value as? String, node.placeholderValue].compactMap { $0 }
            for text in texts where LocalizationUITests.containsJapanese(text) {
                found.append("[\(node.identifier)] \(text)")
            }
            stack.append(contentsOf: node.children)
        }
        XCTAssertTrue(found.isEmpty, "\(screen) に日本語が残っている: \(found)", line: line)
    }

    // MARK: - 写真に保存（「追加のみ」の権限）

    /// 写真に保存（4:5）では、写真ライブラリへの「追加のみ」の権限を求める（読み取りの権限は求めない。S4）
    func testSaveToPhotosRequestsAddOnlyPermission() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = UITestLanguage.japanese + ["-UITestReset", "-SeedBooks", genreSeed]
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        app.buttons["shelf.share"].tap()
        waitForDestinations(app, title: "この棚を共有")
        openPreview(app, "photos", title: "写真に保存（4:5）")
        XCTAssertFalse(app.buttons["share.post"].exists)
        app.buttons["share.save"].tap()

        // OS の許可ダイアログ（SpringBoard）。「追加」の文言（would like to add to your Photos）で、読み取り（access）ではない
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "写真の許可ダイアログが出ない")
        let label = alert.label
        let lowered = label.lowercased()
        XCTAssertTrue(lowered.contains("add to") || label.contains("追加"), label)
        XCTAssertFalse(lowered.contains("access") || label.contains("アクセス"), label)
        let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"])).firstMatch
        XCTAssertTrue(allow.exists, alert.debugDescription)
        allow.tap()
        wait(element(app, "share.status"), "label == '写真に保存しました'", timeout: 15)
    }
}
