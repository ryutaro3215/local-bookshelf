import XCTest

/// 閲覧画面の UI テスト（plan T6 の acceptance ①〜⑤ と F6-9 のスクラバー）。
/// 起動引数 `-UITestReset` でまっさらなデータから始め、`-SeedBooks` で架空の本（合成の表紙）を入れる
@MainActor
final class ShelfUITests: XCTestCase {
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

    private func title(_ app: XCUIApplication) -> String {
        app.buttons["shelf.title"].label
    }

    /// 棚をかえて、棚の名前が変わるのを待つ（変わらなければ同じ名前のまま）
    private func swipeShelf(_ app: XCUIApplication, up: Bool) -> String {
        let before = title(app)
        let carousel = app.collectionViews["shelf.carousel"]
        let target = carousel.exists ? carousel : element(app, "wishlist.empty")
        if up { target.swipeUp() } else { target.swipeDown() }
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before), object: app.buttons["shelf.title"])
        _ = XCTWaiter().wait(for: [changed], timeout: 2)
        return title(app)
    }

    private func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }

    // MARK: - ①

    /// 縦スワイプの対象は本が1冊以上ある棚と買いたい本だけ。「買いたい」の本しかないジャンルは出ない
    func testVerticalSwipeShowsOnlyShelvesWithBooks() {
        let app = launch(seed: "小説:2,エッセイ:0+1,哲学・思想:1")
        XCTAssertEqual(title(app), "小説")
        var seen = [title(app)]
        for _ in 0..<3 {
            seen.append(swipeShelf(app, up: true))
        }
        // 小説 → 哲学・思想 → 買いたい本 で止まる（エッセイ・0冊の未分類は出ない）
        XCTAssertEqual(seen, ["小説", "哲学・思想", "買いたい本", "買いたい本"])
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
        // 下へスワイプで戻る
        XCTAssertEqual(swipeShelf(app, up: false), "哲学・思想")
        XCTAssertEqual(swipeShelf(app, up: false), "小説")
        XCTAssertEqual(swipeShelf(app, up: false), "小説")
    }

    /// 買いたい本は0冊でも出し、案内文を出す（M-2）
    func testEmptyWishlistIsShownWithGuidance() {
        let app = launch(seed: "小説:1")
        XCTAssertEqual(swipeShelf(app, up: true), "買いたい本")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "0冊")
        XCTAssertEqual(element(app, "wishlist.emptyTitle").label, "買いたい本はまだありません")
        XCTAssertTrue(element(app, "wishlist.emptyMessage").label.contains("「購入済み」のチェックを外すと"))
        // 買いたい本の棚には共有マークを出さない
        XCTAssertFalse(app.buttons["shelf.share"].exists)
        XCTAssertEqual(swipeShelf(app, up: false), "小説")
        XCTAssertTrue(app.buttons["shelf.share"].exists)
    }

    // MARK: - ②

    func testShelfPickerListsShelvesWithCategoriesAndCounts() {
        let app = launch(seed: "小説:2,哲学・思想:3,数学:1")
        app.buttons["shelf.title"].tap()
        XCTAssertTrue(app.buttons["picker.row.小説"].waitForExistence(timeout: 5))
        // 分類の見出し
        for category in ["文芸", "人文", "自然科学", "その他"] {
            XCTAssertTrue(element(app, "picker.category.\(category)").exists, category)
        }
        XCTAssertFalse(element(app, "picker.category.社会").exists)
        // 冊数
        XCTAssertEqual(app.buttons["picker.row.小説"].value as? String, "2冊")
        XCTAssertEqual(app.buttons["picker.row.哲学・思想"].value as? String, "3冊")
        XCTAssertEqual(app.buttons["picker.row.数学"].value as? String, "1冊")
        XCTAssertEqual(app.buttons["picker.row.買いたい本"].value as? String, "0冊")
        // 本が入っていない棚は出ない
        XCTAssertFalse(app.buttons["picker.row.エッセイ"].exists)
        XCTAssertFalse(app.buttons["picker.row.未分類"].exists)
        // 選んだ棚に移る
        app.buttons["picker.row.哲学・思想"].tap()
        wait(app.buttons["shelf.title"], "label == '哲学・思想'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "3冊")
        XCTAssertEqual(app.staticTexts["shelf.position"].label, "1 / 3")
    }

    // MARK: - ③

    func testDisplayMenuSwitchesToGridAndGridSwipeChangesShelf() {
        let app = launch(seed: "小説:4,哲学・思想:2")
        app.buttons["browse.display"].tap()
        let gridItem = app.buttons["menu.mode.grid"]
        XCTAssertTrue(gridItem.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["menu.mode.shelf"].isSelected)
        gridItem.tap()
        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews["shelf.carousel"].exists)
        XCTAssertTrue(element(app, "grid.book.3").waitForExistence(timeout: 5))
        // 左右スワイプで棚がかわる
        grid.swipeLeft()
        wait(app.buttons["shelf.title"], "label == '哲学・思想'")
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "grid.book.2").exists)
        app.collectionViews["grid"].swipeRight()
        wait(app.buttons["shelf.title"], "label == '小説'")
        // 棚表示に戻せる
        app.buttons["browse.display"].tap()
        app.buttons["menu.mode.shelf"].tap()
        XCTAssertTrue(app.collectionViews["shelf.carousel"].waitForExistence(timeout: 5))
    }

    // MARK: - ④

    func testDetailShowsDataAndPurchaseDateOnlyForOwnedBooks() {
        let app = launch(seed: "小説:1+1")
        let bookTitle = app.staticTexts["shelf.bookTitle"].label
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "detail.title").label, bookTitle)
        XCTAssertTrue(element(app, "detail.cover").exists)
        XCTAssertTrue(element(app, "detail.genre").label.contains("小説"))
        XCTAssertTrue(element(app, "detail.ownership").label.contains("購入済み"))
        XCTAssertTrue(element(app, "detail.purchaseDate").label.contains(today()))
        // データ追加日は出さない
        XCTAssertEqual(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '追加'")).count, 0)
        XCTAssertTrue(app.buttons["detail.back"].label.contains("小説"))
        app.buttons["detail.back"].tap()

        // 買いたい本: 購入日は出さない
        app.buttons["shelf.title"].tap()
        app.buttons["picker.row.買いたい本"].tap()
        wait(app.buttons["shelf.title"], "label == '買いたい本'")
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(element(app, "detail.ownership").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "detail.ownership").label.contains("買いたい"))
        XCTAssertTrue(element(app, "detail.genre").label.contains("小説"))
        XCTAssertFalse(element(app, "detail.purchaseDate").exists)
        XCTAssertEqual(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '追加日'")).count, 0)
    }

    // MARK: - ⑤

    func testVoiceOverLabelIsTheTitle() {
        let app = launch(seed: "小説:3")
        let center = app.staticTexts["shelf.bookTitle"].label
        XCTAssertFalse(center.isEmpty)
        XCTAssertEqual(element(app, "shelf.book.0").label, center)
        // 横の本も題名で読み上げる
        element(app, "shelf.book.1").tap()
        wait(app.staticTexts["shelf.position"], "label == '2 / 3'")
        XCTAssertEqual(element(app, "shelf.book.1").label, app.staticTexts["shelf.bookTitle"].label)
        // グリッドでも題名
        app.buttons["browse.display"].tap()
        app.buttons["menu.mode.grid"].tap()
        let cell = element(app, "grid.book.0")
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertEqual(cell.label, center)
    }

    // MARK: - F6-9 スクラバー

    func testScrubberAppearsOnShelvesWithAHundredBooks() {
        let app = launch(seed: "小説:100,哲学・思想:99")
        let scrubber = element(app, "shelf.scrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 10))
        XCTAssertEqual(scrubber.value as? String, "1 / 100")
        // 右端までなぞって指を離すと、最後の本へ移る
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.1, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        wait(app.staticTexts["shelf.position"], "label == '100 / 100'")
        // 99冊の棚には出さない
        XCTAssertEqual(swipeShelf(app, up: true), "哲学・思想")
        XCTAssertFalse(element(app, "shelf.scrubber").exists)
    }
}
