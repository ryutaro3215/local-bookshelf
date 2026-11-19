import XCTest

/// 未分類をジャンルに分ける（F5-4。2026-11-20 オーナー指示）。
/// 未分類の棚で開き、本ごとにジャンルを選んで「保存」でまとめて移す。選ばなかった本は未分類に残る
@MainActor
final class SortIntoGenresUITests: XCTestCase {
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

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sort.row.'"))
    }

    /// 行のメニューを開いてジャンルを選ぶ
    private func choose(_ app: XCUIApplication, row: Int, genre: String) {
        rows(app).element(boundBy: row).tap()
        let item = app.buttons[genre].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), genre)
        item.tap()
        wait(rows(app).element(boundBy: row), "value == '\(genre)'")
    }

    func testSortUnsortedBooksIntoGenresAtOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.japanese + ["-UITestReset", "-SeedBooks", "エッセイ:1,未分類:3"]
        app.launch()
        let title = app.buttons["shelf.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        // ジャンルの棚には出さない
        XCTAssertFalse(element(app, "shelf.sortIntoGenres").exists)
        title.tap()
        XCTAssertTrue(app.buttons["picker.row.未分類"].waitForExistence(timeout: 5))
        app.buttons["picker.row.未分類"].tap()
        wait(title, "label == '未分類'")

        // 未分類の棚の左上のマークで開く
        element(app, "shelf.sortIntoGenres").tap()
        XCTAssertTrue(element(app, "sort.title").waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 3)
        XCTAssertFalse(app.buttons["sort.save"].isEnabled, "選ぶまで保存できない")

        // 2冊にジャンルを選んで保存 → 1冊は未分類に残る
        choose(app, row: 0, genre: "詩歌")
        choose(app, row: 1, genre: "漫画")
        wait(element(app, "sort.summary"), "label == '3冊のうち2冊のジャンルを選びました'")
        shot(app, "sort_chosen")
        app.buttons["sort.save"].tap()
        wait(title, "label == '未分類'")
        wait(title, "value == '1冊'")
        shot(app, "sort_saved")

        // 「表示」メニューからも開ける。残りの1冊も分けると、未分類は消えて移した先の棚を見せる
        app.buttons["browse.display"].tap()
        XCTAssertTrue(app.buttons["menu.sortIntoGenres"].waitForExistence(timeout: 5))
        app.buttons["menu.sortIntoGenres"].tap()
        XCTAssertTrue(element(app, "sort.title").waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 1)
        choose(app, row: 0, genre: "詩歌")
        app.buttons["sort.save"].tap()
        wait(title, "label == '詩歌'")
        wait(title, "value == '2冊'")

        title.tap()
        XCTAssertTrue(app.buttons["picker.row.漫画"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["picker.row.未分類"].exists)
    }
}
