import XCTest

/// 検索（plan T10。E-4 結果・E-5 0件）。
/// 起動引数 `-UITestReset` でまっさらなデータから始め、`-SeedBooks` で架空の本（合成の表紙）を入れる。
/// 入る本（DebugSeed.title の番号順）: 小説「灰色の標本箱の記録」「遠い観測所と午後」、エッセイ「静かな図書係の問題」（購入済み）・
/// 「四角い灯台をめぐって」（買いたい）
@MainActor
final class SearchUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-SeedBooks", "小説:2,エッセイ:1+1"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        element(app, "browse.search").tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func replaceQuery(_ app: XCUIApplication, with text: String) {
        let field = app.textFields["search.field"]
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    /// よみの部分一致で出て、押すと詳細。戻ると検索に戻る
    func testYomiMatchOpensDetail() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("かんそく")
        let first = element(app, "search.result.0")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "遠い観測所と午後")
        XCTAssertFalse(element(app, "search.result.1").exists)
        XCTAssertEqual(element(app, "search.count").label, "1件（題名・よみの一部に一致）")
        first.tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "detail.title").label, "遠い観測所と午後")
        app.buttons["detail.back"].tap()
        XCTAssertTrue(element(app, "search.result.0").waitForExistence(timeout: 5))
        app.buttons["search.cancel"].tap()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 5))
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.textFields["search.field"])
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed)
    }

    /// 題名の部分一致は全ジャンルから。カタカナ・ひらがなを区別しない
    func testTitleMatchAcrossGenres() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("い")  // 3冊ともよみに「い」を含む
        XCTAssertTrue(element(app, "search.result.2").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "search.result.3").exists)  // 買いたい本「四角い灯台をめぐって」は出ない
        let titles = (0..<3).map { element(app, "search.result.\($0)").label }
        XCTAssertEqual(Set(titles), ["灰色の標本箱の記録", "遠い観測所と午後", "静かな図書係の問題"])
        replaceQuery(app, with: "トショ")
        XCTAssertTrue(element(app, "search.result.0").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "search.result.0").label, "静かな図書係の問題")
    }

    /// 0件（E-5）: 案内「題名やよみの一部だけでも検索できます」が出る。「買いたい」の本だけに一致しても0件
    func testZeroResultsShowsGuidance() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("灯台")
        let hint = element(app, "search.empty.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertEqual(hint.label, "題名やよみの一部だけでも検索できます")
        XCTAssertEqual(element(app, "search.empty.title").label, "「灯台」に一致する本はありません")
        XCTAssertFalse(element(app, "search.result.0").exists)
        replaceQuery(app, with: "量子")
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "search.empty.title").label, "「量子」に一致する本はありません")
    }
}
