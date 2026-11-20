import XCTest

/// 購入月別の UI テスト（plan T13 の acceptance。F6-7）。
/// 起動引数 `-SeedBooks` の「@YYYY-MM-DD」で、購入日をその日から1日ずつずらした架空の本を入れる
@MainActor
final class MonthModeUITests: XCTestCase {
    /// 2026年11月: 2冊（哲学・思想）／2026年10月: 3冊（小説）／2025年12月: 2冊（エッセイ）／買いたい本 1冊（出ない）
    private let seed = "小説:3@2026-10-05,哲学・思想:2@2026-11-02,エッセイ:2@2025-12-30,小説:0+1"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch() -> XCUIApplication {
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

    private func openMenu(_ app: XCUIApplication) {
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu").waitForExistence(timeout: 5))
    }

    /// 「表示」→「購入月別」
    private func switchToMonth(_ app: XCUIApplication) {
        openMenu(app)
        element(app, "menu.group.month").tap()
        XCTAssertTrue(element(app, "month.title").waitForExistence(timeout: 5))
    }

    private func monthTitle(_ app: XCUIApplication) -> XCUIElement {
        element(app, "month.title")
    }

    // MARK: - 切り替え・上部の名前・「並べ順」

    /// 「表示」→「購入月別」で切り替わる。上部の月の名前に「▾」が無く押しても一覧は開かない。「並べ順」は出ない
    func testSwitchToMonthModeWithoutChevronAndSortOrder() {
        let app = launch()
        // ジャンル別では棚の名前に「▾」が付いたボタン（棚一覧を開く）
        XCTAssertEqual(app.buttons["shelf.title"].label, "小説")
        switchToMonth(app)

        // いちばん新しい月から。名前はボタンではなく、「▾」も無い
        let title = monthTitle(app)
        XCTAssertEqual(title.label, "2026年11月")
        XCTAssertEqual(title.value as? String, "2冊")
        XCTAssertFalse(app.buttons["month.title"].exists)
        XCTAssertFalse(app.buttons["shelf.title"].exists)
        XCTAssertFalse(app.images["chevron.down"].exists)
        XCTAssertFalse(title.label.contains("▾"))
        title.tap()
        XCTAssertFalse(element(app, "picker.row.小説").waitForExistence(timeout: 1.5))

        // 本の情報: 題名 → ジャンル・購入日 → 位置（購入日の古い順の1冊目）
        let meta = element(app, "shelf.bookMeta").label
        XCTAssertTrue(meta.hasPrefix("哲学・思想・2026.11.02"), meta)
        XCTAssertTrue(meta.hasSuffix("購入"), meta)
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 2")
        XCTAssertTrue(app.buttons["shelf.share"].exists)

        // 「表示」メニュー: 購入月別にチェック、「並べ順」は出ない
        openMenu(app)
        XCTAssertTrue(element(app, "menu.group.month").isSelected)
        XCTAssertFalse(element(app, "menu.group.genre").isSelected)
        XCTAssertFalse(element(app, "menu.sort.manual").exists)
        XCTAssertFalse(element(app, "menu.sort.title").exists)
        // ジャンル別に戻すと「並べ順」がまた出る
        element(app, "menu.group.genre").tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))
        openMenu(app)
        XCTAssertTrue(element(app, "menu.sort.manual").exists)
    }

    /// 縦スワイプで月を移動する（本のない月・「買いたい」の本は出ない）。横の並びは購入日の古い順
    func testVerticalSwipeMovesBetweenMonths() {
        let app = launch()
        switchToMonth(app)
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        let title = monthTitle(app)

        carousel.swipeUp()
        wait(title, "label == '2026年10月'")
        XCTAssertEqual(title.value as? String, "3冊")
        XCTAssertTrue(element(app, "shelf.bookMeta").label.hasPrefix("小説・2026.10.05"))
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 3")
        // 右の本を押して中央へ（横にめくる）。次の日に買った本
        element(app, "shelf.book.1").tap()
        wait(element(app, "shelf.bookMeta"), "label BEGINSWITH '小説・2026.10.06'")

        carousel.swipeUp()
        wait(title, "label == '2025年12月'")
        XCTAssertEqual(title.value as? String, "2冊")
        // いちばん古い月で止まる
        carousel.swipeUp()
        sleep(1)
        XCTAssertEqual(title.label, "2025年12月")

        carousel.swipeDown()
        wait(title, "label == '2026年10月'")
        carousel.swipeDown()
        wait(title, "label == '2026年11月'")
    }

    /// 長押しで選ぶと、別の棚へ・削除はできるが並べ替えの矢印は出ない
    func testLongPressAllowsMoveAndDeleteButNotReorder() {
        let app = launch()
        switchToMonth(app)
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        carousel.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["select.move"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["select.delete"].exists)
        XCTAssertFalse(app.buttons["select.left"].exists)
        XCTAssertFalse(app.buttons["select.right"].exists)
        // 削除の確認を出して、取り消す
        app.buttons["select.delete"].tap()
        XCTAssertTrue(element(app, "delete.cancel").waitForExistence(timeout: 5))
        element(app, "delete.cancel").tap()
        XCTAssertEqual(monthTitle(app).value as? String, "2冊")
    }

    // MARK: - ピンチ

    /// 棚表示: ピンチインで年、ピンチアウトで月に戻る（同じ本を見せる）
    func testPinchSwitchesBetweenMonthAndYear() {
        let app = launch()
        switchToMonth(app)
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        let title = monthTitle(app)
        // 2026年10月の2冊目を見ておく（右の本を押して中央へ）
        carousel.swipeUp()
        wait(title, "label == '2026年10月'")
        element(app, "shelf.book.1").tap()
        wait(element(app, "shelf.position"), "label == '2 / 3'")

        carousel.pinch(withScale: 0.4, velocity: -1)
        wait(title, "label == '2026年'")
        XCTAssertEqual(title.value as? String, "5冊")
        // 2026年: 10月の3冊 → 11月の2冊。見ていた本（10月の2冊目）のまま
        XCTAssertEqual(element(app, "shelf.position").label, "2 / 5")
        XCTAssertTrue(element(app, "month.tab.10").isSelected)
        XCTAssertTrue(element(app, "month.tab.11").exists)
        // 年の名前も押せない（▾ なし）
        XCTAssertFalse(app.buttons["month.title"].exists)
        // 月の名前を押すと、その月の最初の本へ
        element(app, "month.tab.11").tap()
        wait(element(app, "shelf.position"), "label == '4 / 5'")
        // 縦スワイプで年をかえる
        carousel.swipeUp()
        wait(title, "label == '2025年'")
        carousel.swipeDown()
        wait(title, "label == '2026年'")
        // 年をかえるとその年の最初の本（10月の1冊目）から
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 5")

        // ピンチアウトで、見ている本の月に戻る
        carousel.pinch(withScale: 2.5, velocity: 1)
        wait(title, "label == '2026年10月'")
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 3")
        XCTAssertFalse(element(app, "month.tab.10").exists)
    }

    /// グリッド表示: 月の見出しの縦スクロール。ピンチインで年（1行5冊）、ピンチアウトで月に戻る
    func testGridPinchSwitchesBetweenMonthAndYear() {
        let app = launch()
        openMenu(app)
        element(app, "menu.mode.grid").tap()
        switchToMonthInGrid(app)
        XCTAssertTrue(element(app, "monthGrid.header.2026-11").exists)
        XCTAssertTrue(element(app, "monthGrid.header.2026-10").exists)
        // 月のグリッドは題名つき。1冊目は11月の最初の本
        XCTAssertTrue(element(app, "grid.book.0").exists)
        XCTAssertFalse(app.buttons["month.title"].exists)

        let grid = element(app, "monthGrid")
        grid.pinch(withScale: 0.4, velocity: -1)
        XCTAssertTrue(element(app, "monthGrid.header.2026").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "monthGrid.header.2025").exists)
        XCTAssertFalse(element(app, "monthGrid.header.2026-11").exists)

        grid.pinch(withScale: 2.5, velocity: 1)
        XCTAssertTrue(element(app, "monthGrid.header.2026-11").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "monthGrid.header.2026").exists)

        // 本をタップすると詳細（戻る先は月の名前）
        element(app, "grid.book.0").tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.back"].label, "2026年11月に戻る")
    }

    private func switchToMonthInGrid(_ app: XCUIApplication) {
        openMenu(app)
        element(app, "menu.group.month").tap()
        XCTAssertTrue(element(app, "monthGrid").waitForExistence(timeout: 5))
    }

    // MARK: - 題名の下の横スワイプ（2026-11-20 オーナー指示）

    /// 購入月別でも、書影の下を横にスワイプすると本をめくれる（ジャンル別の棚表示と同じ）
    func testHorizontalSwipeBelowCoversFlipsBooks() {
        let app = launch()
        switchToMonth(app)
        let position = element(app, "shelf.position")
        XCTAssertEqual(position.label, "1 / 2")
        element(app, "shelf.bookTitle").swipeLeft()
        wait(position, "label == '2 / 2'")
        element(app, "shelf.bookTitle").swipeRight()
        wait(position, "label == '1 / 2'")
        XCTAssertEqual(monthTitle(app).label, "2026年11月")
    }
}
