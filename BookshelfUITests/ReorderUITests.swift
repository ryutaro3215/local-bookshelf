import XCTest

/// 並べ替え・棚間移動・削除・一括整列の UI テスト（plan T7 の acceptance ①〜③ と、グリッドの長押しメニュー・並べ順）。
/// 起動引数 `-UITestReset` でまっさらなデータから始め、`-SeedBooks` で架空の本（合成の表紙）を入れる
@MainActor
final class ReorderUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(seed: String, persistent: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-SeedBooks", seed] + (persistent ? ["-UITestPersistentStore"] : [])
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

    /// 棚表示に並んでいる本の題名（shelf.book.0 から順に）
    private func shelfTitles(_ app: XCUIApplication, count: Int) -> [String] {
        (0..<count).map { element(app, "shelf.book.\($0)").label }
    }

    /// 中央の本を長押しし、そのまま指を (dx, dy) だけ動かして離す
    private func pressAndDrag(_ app: XCUIApplication, dx: CGFloat, dy: CGFloat) {
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        let start = carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)), withVelocity: .slow,
            thenHoldForDuration: 0.3)
    }

    // MARK: - ①

    /// 長押し＋横スワイプで位置が変わり、アプリを再起動しても保たれる
    func testLongPressAndHorizontalSwipeReordersAndPersists() {
        let app = launch(seed: "哲学・思想:4", persistent: true)
        wait(element(app, "shelf.book.3"), "exists == true")
        let before = shelfTitles(app, count: 4)
        XCTAssertEqual(element(app, "shelf.bookTitle").label, before[0])
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 4")

        // 右へ2冊分（1冊 60pt）ドラッグ → 1冊目が3番目へ
        pressAndDrag(app, dx: 150, dy: 0)
        // 指を離しても選択は続く（D-1）。選んだ本が中央のまま
        wait(element(app, "select.state"), "exists == true")
        XCTAssertEqual(element(app, "shelf.bookTitle").label, before[0])
        // タップで選択を解除すると、位置は 3 / 4
        element(app, "shelf.bookTitle").tap()
        wait(element(app, "shelf.position"), "label == '3 / 4'")
        let expected = [before[1], before[2], before[0], before[3]]
        wait(element(app, "shelf.book.2"), "label == '\(before[0])'")
        XCTAssertEqual(shelfTitles(app, count: 4), expected)

        // 再起動（同じデータを開く）
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-UITestPersistentStore"]
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["shelf.title"].waitForExistence(timeout: 20))
        XCTAssertEqual(relaunched.buttons["shelf.title"].label, "哲学・思想")
        wait(element(relaunched, "shelf.book.3"), "exists == true")
        XCTAssertEqual(shelfTitles(relaunched, count: 4), expected)
    }

    // MARK: - ②

    /// 長押し＋上スワイプで「移動先の棚を選ぶ」（0冊のジャンルも出る）から別の棚へ移り、「取り消す」で戻る
    func testLongPressAndSwipeUpMovesToAnotherShelfAndUndoRestores() {
        let app = launch(seed: "哲学・思想:3")
        wait(element(app, "shelf.book.2"), "exists == true")
        let before = shelfTitles(app, count: 3)
        // 2冊目を中央に
        element(app, "shelf.book.1").tap()
        wait(element(app, "shelf.position"), "label == '2 / 3'")

        pressAndDrag(app, dx: 0, dy: -150)
        XCTAssertTrue(element(app, "move.title").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "move.title").label, "移動先の棚を選ぶ")
        // 0冊のジャンルも出る。今の棚は「現在の棚」で選べない
        XCTAssertEqual(element(app, "move.row.宗教").value as? String, "0冊")
        XCTAssertEqual(element(app, "move.row.歴史").value as? String, "0冊")
        XCTAssertEqual(element(app, "move.row.哲学・思想").value as? String, "現在の棚")
        XCTAssertFalse(element(app, "move.row.買いたい本").exists)
        XCTAssertFalse(element(app, "move.confirm").isEnabled)

        element(app, "move.row.歴史").tap()
        wait(element(app, "move.confirm"), "label == '歴史 へ移動'")
        element(app, "move.confirm").tap()

        // 移動先の棚の末尾（D-3）と取り消しのトースト
        wait(app.buttons["shelf.title"], "label == '歴史'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
        XCTAssertEqual(element(app, "shelf.bookTitle").label, before[1])
        XCTAssertEqual(element(app, "toast.message").label, "歴史 に移しました")

        element(app, "toast.undo").tap()
        wait(app.buttons["shelf.title"], "label == '哲学・思想'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "3冊")
        // 元の位置（2 / 3）に戻る
        wait(element(app, "shelf.position"), "label == '2 / 3'")
        XCTAssertEqual(element(app, "shelf.bookTitle").label, before[1])
        XCTAssertEqual(shelfTitles(app, count: 3), before)
        XCTAssertFalse(element(app, "toast").exists)
    }

    // MARK: - ③

    /// 長押し＋下スワイプで確認ダイアログが出て、削除で本が消える
    func testLongPressAndSwipeDownAsksAndDeletes() {
        let app = launch(seed: "哲学・思想:3")
        wait(element(app, "shelf.book.2"), "exists == true")
        let before = shelfTitles(app, count: 3)

        // キャンセルでは消えない
        pressAndDrag(app, dx: 0, dy: 150)
        XCTAssertTrue(element(app, "delete.dialog").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "delete.title").label, "「\(before[0])」を\n削除しますか？")
        element(app, "delete.cancel").tap()
        wait(element(app, "delete.dialog"), "exists == false")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "3冊")

        pressAndDrag(app, dx: 0, dy: 150)
        XCTAssertTrue(element(app, "delete.dialog").waitForExistence(timeout: 5))
        element(app, "delete.confirm").tap()
        wait(app.buttons["shelf.title"], "value == '2冊'")
        wait(element(app, "shelf.book.1"), "exists == true")
        XCTAssertEqual(shelfTitles(app, count: 2), [before[1], before[2]])
    }

    // MARK: - グリッドの長押しメニュー（I-2）

    /// グリッドで長押しするとメニュー（詳細を見る・別の棚へ移動・削除）が出て、削除できる
    func testGridLongPressMenu() {
        let app = launch(seed: "哲学・思想:3")
        app.buttons["browse.display"].tap()
        element(app, "menu.mode.grid").tap()
        let second = element(app, "grid.book.1")
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let title = second.label

        second.press(forDuration: 1.0)
        XCTAssertTrue(element(app, "gridMenu").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "gridMenu.detail").label, "詳細を見る")
        XCTAssertEqual(element(app, "gridMenu.move").label, "別の棚へ移動")
        XCTAssertEqual(element(app, "gridMenu.delete").label, "削除")

        // 閉じる → もう一度開いて「別の棚へ移動」でシートが出る
        element(app, "gridMenu.move").tap()
        XCTAssertTrue(element(app, "move.title").waitForExistence(timeout: 5))
        element(app, "move.cancel").tap()
        wait(element(app, "move.title"), "exists == false")

        second.press(forDuration: 1.0)
        XCTAssertTrue(element(app, "gridMenu.delete").waitForExistence(timeout: 5))
        element(app, "gridMenu.delete").tap()
        XCTAssertTrue(element(app, "delete.dialog").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "delete.title").label, "「\(title)」を\n削除しますか？")
        element(app, "delete.confirm").tap()
        wait(app.buttons["shelf.title"], "value == '2冊'")
        XCTAssertNotEqual(element(app, "grid.book.1").label, title)
    }

    /// グリッドで長押ししたままドラッグすると並べ替えられ、メニューは閉じる（I-2「そのままドラッグで並べ替え」）
    func testGridLongPressDragReorders() {
        let app = launch(seed: "哲学・思想:6")
        app.buttons["browse.display"].tap()
        element(app, "menu.mode.grid").tap()
        let first = element(app, "grid.book.0")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let title = first.label
        first.press(
            forDuration: 1.0, thenDragTo: element(app, "grid.book.4"), withVelocity: .slow, thenHoldForDuration: 0.5)
        wait(element(app, "grid.book.4"), "label == '\(title)'")
        XCTAssertFalse(element(app, "gridMenu").exists)
        // 棚表示でも同じ並び（保存されている）
        app.buttons["browse.display"].tap()
        element(app, "menu.mode.shelf").tap()
        wait(element(app, "shelf.book.4"), "label == '\(title)'")
    }

    // MARK: - 一括整列（F5-3）

    /// 「表示」→「この棚の並べ順」で整列でき、「手動」で元の並びに戻る
    func testBulkSortFromDisplayMenu() {
        let app = launch(seed: "哲学・思想:3")
        wait(element(app, "shelf.book.2"), "exists == true")
        let before = shelfTitles(app, count: 3)

        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu.sort.manual").isSelected)
        for key in ["purchasedNewest", "purchasedOldest", "addedNewest", "addedOldest", "title"] {
            XCTAssertTrue(element(app, "menu.sort.\(key)").exists, key)
        }
        element(app, "menu.sort.addedNewest").tap()
        wait(element(app, "shelf.book.0"), "label == '\(before[2])'")
        XCTAssertEqual(shelfTitles(app, count: 3), before.reversed())

        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu.sort.addedNewest").isSelected)
        element(app, "menu.sort.manual").tap()
        wait(element(app, "shelf.book.0"), "label == '\(before[0])'")
        XCTAssertEqual(shelfTitles(app, count: 3), before)
    }

    /// 買いたい本が0冊の画面でも、グリッド表示では左右スワイプで棚をかえられる（N-052）
    func testEmptyWishlistRespondsToHorizontalSwipeInGrid() {
        let app = launch(seed: "小説:1")
        app.buttons["browse.display"].tap()
        element(app, "menu.mode.grid").tap()
        XCTAssertTrue(element(app, "grid").waitForExistence(timeout: 5))
        element(app, "grid").swipeLeft()
        wait(app.buttons["shelf.title"], "label == '買いたい本'")
        element(app, "wishlist.empty").swipeRight()
        wait(app.buttons["shelf.title"], "label == '小説'")
    }

    // MARK: - 買いたい本の棚（N-063）

    /// 買いたい本の棚では横の並べ替えをせず、並べ順のメニューも出ない。
    /// 「買いたい」の本を別の棚へ移しても、買いたい本の棚に残る（ジャンルだけが変わる。§10.3）
    func testWishlistShelfDoesNotReorderAndKeepsMovedBook() {
        let app = launch(seed: "小説:1+3")
        app.buttons["shelf.title"].tap()
        app.buttons["picker.row.買いたい本"].tap()
        wait(app.buttons["shelf.title"], "label == '買いたい本'")
        wait(element(app, "shelf.book.2"), "exists == true")
        let before = shelfTitles(app, count: 3)
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 3")

        // 長押し＋横スワイプでは位置が変わらない
        pressAndDrag(app, dx: 150, dy: 0)
        wait(element(app, "select.state"), "exists == true")
        element(app, "shelf.bookTitle").tap()
        wait(element(app, "select.state"), "exists == false")
        XCTAssertEqual(element(app, "shelf.position").label, "1 / 3")
        XCTAssertEqual(shelfTitles(app, count: 3), before)

        // 並べ順のメニューを出さない
        app.buttons["browse.display"].tap()
        XCTAssertTrue(element(app, "menu.mode.shelf").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "menu.sort.manual").exists)
        XCTAssertFalse(element(app, "menu.sort.title").exists)
        element(app, "menu.mode.shelf").tap()
        wait(element(app, "menu"), "exists == false")

        // 別の棚（歴史）へ移しても、買いたい本の棚に残り、ジャンルが歴史になる
        pressAndDrag(app, dx: 0, dy: -150)
        XCTAssertTrue(element(app, "move.row.歴史").waitForExistence(timeout: 5))
        element(app, "move.row.歴史").tap()
        element(app, "move.confirm").tap()
        wait(element(app, "toast.message"), "label == '歴史 に移しました'")
        XCTAssertEqual(app.buttons["shelf.title"].label, "買いたい本")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "3冊")
        XCTAssertEqual(shelfTitles(app, count: 3), before)
        XCTAssertEqual(element(app, "shelf.bookTitle").label, before[0])
        XCTAssertTrue(element(app, "shelf.bookMeta").label.contains("歴史"))
        // 「買いたい」の本しか無い歴史は閲覧画面に出ない
        app.buttons["shelf.title"].tap()
        XCTAssertFalse(app.buttons["picker.row.歴史"].exists)
    }

    /// 移した直後にその本を削除すると取り消しのトーストが消え、元の棚の並びは変わらない（N-060・N-063）
    func testMoveThenDeleteDismissesUndo() {
        let app = launch(seed: "哲学・思想:3")
        wait(element(app, "shelf.book.2"), "exists == true")
        let before = shelfTitles(app, count: 3)

        pressAndDrag(app, dx: 0, dy: -150)
        XCTAssertTrue(element(app, "move.row.歴史").waitForExistence(timeout: 5))
        element(app, "move.row.歴史").tap()
        element(app, "move.confirm").tap()
        wait(app.buttons["shelf.title"], "label == '歴史'")
        XCTAssertTrue(element(app, "toast.undo").exists)

        // トーストが出ている間に、移した本を削除する
        pressAndDrag(app, dx: 0, dy: 150)
        XCTAssertTrue(element(app, "delete.dialog").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "delete.title").label, "「\(before[0])」を\n削除しますか？")
        element(app, "delete.confirm").tap()
        wait(element(app, "toast"), "exists == false", timeout: 3)
        XCTAssertFalse(element(app, "toast.undo").exists)

        // 歴史は空になって消え、元の棚は残りの2冊のまま
        wait(app.buttons["shelf.title"], "label == '哲学・思想'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "2冊")
        XCTAssertEqual(shelfTitles(app, count: 2), [before[1], before[2]])
    }
}
