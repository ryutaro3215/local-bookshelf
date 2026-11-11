import XCTest

/// 撮影登録フローの UI テスト（plan T5 の acceptance ①〜⑧）。
/// カメラはシミュレータに無いため、起動引数 `-FakeCamera` で架空の表紙の合成画像を「撮影」する。
/// 起動引数 `-UITestReset` で毎回まっさらなデータから始める。入口は仮の画面（ContentView。T6 で閲覧画面に置き換え）
@MainActor
final class CaptureFlowUITests: XCTestCase {
    private let covers = "cover:PAPER COMETS,cover:THE QUIET ORCHARD,cover:NORTHERN LANTERNS"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-FakeCamera", scenario]
        app.launch()
        return app
    }

    /// 仮の画面の要素を、見えるまでスクロールしてから押す
    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) が見つからない")
        element.tap()
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 20) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element): \(predicate)")
    }

    /// 入口（＋ または棚の末尾の空き枠）→ 登録方法のシート
    private func openMethodSheet(_ app: XCUIApplication, slot: String? = nil) {
        if let slot {
            tapScrolling(app.buttons["host.slot.\(slot)"], in: app)
        } else {
            app.buttons["host.add"].tap()
        }
        XCTAssertTrue(app.buttons["register.camera"].waitForExistence(timeout: 5))
    }

    private func openCamera(_ app: XCUIApplication) {
        app.buttons["register.camera"].tap()
        XCTAssertTrue(app.buttons["capture.shutter"].waitForExistence(timeout: 10))
    }

    private func shoot(_ app: XCUIApplication, times: Int) {
        let shutter = app.buttons["capture.shutter"]
        for _ in 0..<times {
            wait(shutter, "isEnabled == true")
            shutter.tap()
        }
    }

    /// 登録待ちの一覧で、題名の読み取りが終わるのを待ち、空の題名には架空の題名を入れる
    private func fillMissingTitles(_ app: XCUIApplication, count: Int) {
        for i in 0..<count {
            XCTAssertTrue(app.textFields["pending.row.\(i).title"].waitForExistence(timeout: 30))
        }
        let reading = app.staticTexts["題名を読み取り中…"]
        wait(reading, "exists == false", timeout: 90)
        for i in 0..<count {
            let field = app.textFields["pending.row.\(i).title"]
            let value = field.value as? String ?? ""
            if value.isEmpty || value == "題名を入力" {
                field.tap()
                field.typeText("Fictional Book \(i)")
            }
        }
        app.staticTexts["pending.heading"].tap()
    }

    private func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - ①

    func testContinuousCaptureListsThreeBooksWithoutClosingCamera() {
        let app = launch(scenario: covers)
        openMethodSheet(app)
        openCamera(app)
        shoot(app, times: 3)
        // カメラを閉じずに3冊撮れている
        XCTAssertTrue(app.buttons["capture.shutter"].exists)
        wait(app.staticTexts["capture.count"], "label CONTAINS '3 / 30冊'")
        app.buttons["capture.done"].tap()
        for i in 0..<3 {
            XCTAssertTrue(app.buttons["pending.row.\(i).check"].waitForExistence(timeout: 30), "row \(i)")
        }
        XCTAssertFalse(app.buttons["pending.row.3.check"].exists)
        XCTAssertEqual(app.staticTexts["pending.heading"].label, "登録待ち 3 / 30冊")
        // ライブラリから選べるのは残りの冊数まで（F1-8）
        XCTAssertEqual(app.buttons["pending.addLibrary"].value as? String, "残り27冊まで選べます")
    }

    // MARK: - ②

    func testPurchasedChecksAndRegistration() {
        let app = launch(scenario: covers)
        openMethodSheet(app)
        // 登録先のジャンルを選ぶ
        app.buttons["register.destination"].tap()
        app.buttons["哲学・思想"].tap()
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "哲学・思想")
        openCamera(app)
        shoot(app, times: 3)
        app.buttons["capture.done"].tap()
        fillMissingTitles(app, count: 3)

        // 初期状態は全冊が購入済み
        XCTAssertEqual(app.staticTexts["pending.ownedCount"].label, "購入済み 3 / 3冊")
        for i in 0..<3 {
            XCTAssertEqual(app.buttons["pending.row.\(i).check"].value as? String, "オン")
        }
        // すべて解除で全冊が外れる
        app.buttons["pending.deselectAll"].tap()
        XCTAssertEqual(app.staticTexts["pending.ownedCount"].label, "購入済み 0 / 3冊")
        for i in 0..<3 {
            XCTAssertEqual(app.buttons["pending.row.\(i).check"].value as? String, "オフ")
        }
        // すべて選択に戻し、1冊だけ外す
        app.buttons["pending.selectAll"].tap()
        app.buttons["pending.row.0.check"].tap()
        XCTAssertEqual(app.staticTexts["pending.ownedCount"].label, "購入済み 2 / 3冊")
        XCTAssertEqual(app.staticTexts["pending.summary"].label, "購入済み 2冊・買いたい本 1冊")

        let register = app.buttons["pending.register"]
        wait(register, "isEnabled == true")
        register.tap()

        // 外した1冊は買いたい本に、残りは選んだジャンルに購入日＝今日で並ぶ
        XCTAssertTrue(app.buttons["host.add"].waitForExistence(timeout: 10))
        wait(app.staticTexts["host.count.哲学・思想"], "label == '2冊'")
        let books = app.staticTexts.matching(identifier: "host.book")
        XCTAssertEqual(books.count, 3)
        var wanted = 0
        var owned = 0
        for i in 0..<books.count {
            let label = books.element(boundBy: i).label
            XCTAssertTrue(label.contains("｜哲学・思想｜"), label)
            if label.contains("｜買いたい｜") {
                wanted += 1
                XCTAssertTrue(label.hasSuffix("購入日なし"), label)
            } else {
                owned += 1
                XCTAssertTrue(label.contains("｜購入済み｜"), label)
                XCTAssertTrue(label.hasSuffix(today()), label)
            }
        }
        XCTAssertEqual(wanted, 1)
        XCTAssertEqual(owned, 2)
        tapScrolling(app.staticTexts["host.count.買いたい本"], in: app)
        XCTAssertEqual(app.staticTexts["host.count.買いたい本"].label, "1冊")
    }

    // MARK: - ③

    func testRegisterIsDisabledWhileATitleIsEmpty() {
        let app = launch(scenario: "blank")
        openMethodSheet(app)
        openCamera(app)
        shoot(app, times: 1)
        app.buttons["capture.done"].tap()
        let field = app.textFields["pending.row.0.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        wait(app.staticTexts["題名を読み取り中…"], "exists == false", timeout: 60)

        let register = app.buttons["pending.register"]
        XCTAssertFalse(register.isEnabled)
        XCTAssertEqual(register.label, "題名を入力すると登録できます")
        XCTAssertTrue(app.staticTexts["pending.untitledNotice"].exists)

        field.tap()
        field.typeText("Fictional Atlas")
        app.staticTexts["pending.heading"].tap()
        wait(register, "isEnabled == true")
    }

    // MARK: - ④

    func testEmptySlotSetsDestination() {
        let app = launch(scenario: covers)
        openMethodSheet(app, slot: "エッセイ")
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "エッセイ")
        openCamera(app)
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "エッセイ")
        shoot(app, times: 1)
        app.buttons["capture.done"].tap()
        fillMissingTitles(app, count: 1)
        XCTAssertEqual(app.buttons["pending.row.0.genre"].value as? String, "エッセイ")
        let register = app.buttons["pending.register"]
        wait(register, "isEnabled == true")
        register.tap()
        XCTAssertTrue(app.buttons["host.add"].waitForExistence(timeout: 10))
        wait(app.staticTexts["host.count.エッセイ"], "label == '1冊'")
    }

    // MARK: - ⑤

    func testLastUsedShelfSkipsWishlist() {
        let app = launch(scenario: covers)
        // 使った棚の記録がなければ未分類
        openMethodSheet(app)
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "未分類")
        app.buttons["register.cancel"].tap()
        XCTAssertTrue(app.buttons["host.add"].waitForExistence(timeout: 5))

        // 小説 → 買いたい本 の順に使う。直前は買いたい本なので、それ以外で直前の小説が初期値になる
        tapScrolling(app.buttons["host.visit.小説"], in: app)
        tapScrolling(app.buttons["host.visit.買いたい本"], in: app)
        openMethodSheet(app)
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "小説")
    }

    // MARK: - ⑥

    func testLimitOfThirtyBooks() {
        let app = launch(scenario: covers)
        openMethodSheet(app)
        openCamera(app)
        shoot(app, times: 30)
        let shutter = app.buttons["capture.shutter"]
        wait(shutter, "isEnabled == false", timeout: 5)
        XCTAssertTrue(app.staticTexts["capture.limitMessage"].exists)
        XCTAssertTrue(app.staticTexts["capture.limitMessage"].label.contains("一度に登録できるのは30冊までです"))
        XCTAssertTrue(app.staticTexts["capture.count"].label.contains("30 / 30冊"))
        // ライブラリの選択も残り0冊（選べない）
        let library = app.buttons["capture.library"]
        XCTAssertFalse(library.isEnabled)
        XCTAssertEqual(library.value as? String, "残り0冊まで選べます")

        app.buttons["capture.done"].tap()
        XCTAssertTrue(app.staticTexts["pending.heading"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["pending.heading"].label, "登録待ち 30 / 30冊")
        XCTAssertFalse(app.buttons["pending.addLibrary"].isEnabled)
        XCTAssertFalse(app.buttons["pending.addCamera"].isEnabled)

        // 1冊を外すと残りが戻り、撮影できるようになる
        let firstRow = app.buttons["pending.row.0.check"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30))
        let cell = app.cells.containing(.button, identifier: "pending.row.0.check").firstMatch
        (cell.exists ? cell : firstRow).swipeLeft()
        let remove = app.buttons["外す"].firstMatch
        if !remove.waitForExistence(timeout: 5) {
            print(app.debugDescription)
        }
        XCTAssertTrue(remove.exists)
        remove.tap()
        wait(app.staticTexts["pending.heading"], "label == '登録待ち 29 / 30冊'")
        let addCamera = app.buttons["pending.addCamera"]
        wait(addCamera, "isEnabled == true")
        addCamera.tap()
        wait(app.buttons["capture.shutter"], "isEnabled == true")
        XCTAssertFalse(app.staticTexts["capture.limitMessage"].exists)
    }

    // MARK: - ⑦

    func testCaptureGuideIsShown() {
        let app = launch(scenario: covers)
        openMethodSheet(app)
        openCamera(app)
        let guide = app.staticTexts["capture.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        XCTAssertTrue(guide.label.contains("表紙全体が枠に入るように合わせてください"))
        XCTAssertTrue(guide.label.contains("背景と色の違う所"))
        XCTAssertTrue(app.otherElements["capture.guideFrame"].exists || app.images["capture.guideFrame"].exists)
    }

    // MARK: - ⑧

    func testManualCornerAdjustmentWhenDetectionFails() {
        let app = launch(scenario: "nocover,cover:PAPER COMETS")
        openMethodSheet(app)
        openCamera(app)
        shoot(app, times: 1)

        let image = app.images["adjust.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["adjust.message"].label.contains("表紙の四隅を見つけられませんでした"))
        // 初期の四隅は画像の各辺から約10%内側
        let frame = image.frame
        let expected: [String: CGPoint] = [
            "topLeft": CGPoint(x: frame.minX + frame.width * 0.1, y: frame.minY + frame.height * 0.1),
            "topRight": CGPoint(x: frame.maxX - frame.width * 0.1, y: frame.minY + frame.height * 0.1),
            "bottomRight": CGPoint(x: frame.maxX - frame.width * 0.1, y: frame.maxY - frame.height * 0.1),
            "bottomLeft": CGPoint(x: frame.minX + frame.width * 0.1, y: frame.maxY - frame.height * 0.1),
        ]
        for (name, point) in expected {
            let handle =
                app.buttons["adjust.handle.\(name)"].exists
                ? app.buttons["adjust.handle.\(name)"] : app.otherElements["adjust.handle.\(name)"]
            XCTAssertTrue(handle.exists, name)
            XCTAssertEqual(handle.frame.midX, point.x, accuracy: 3, name)
            XCTAssertEqual(handle.frame.midY, point.y, accuracy: 3, name)
        }

        // 四隅をドラッグして確定する
        for name in ["topLeft", "bottomRight"] {
            let handle =
                app.buttons["adjust.handle.\(name)"].exists
                ? app.buttons["adjust.handle.\(name)"] : app.otherElements["adjust.handle.\(name)"]
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let delta: CGFloat = name == "topLeft" ? -20 : 20
            start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: delta, dy: delta)))
        }
        let movedFrame =
            app.buttons["adjust.handle.topLeft"].exists
            ? app.buttons["adjust.handle.topLeft"].frame : app.otherElements["adjust.handle.topLeft"].frame
        XCTAssertLessThan(movedFrame.midX, expected["topLeft"]!.x - 10)

        app.buttons["adjust.confirm"].tap()
        wait(image, "exists == false")
        // 補正済みの表紙が登録待ちの一覧に入る
        wait(app.staticTexts["capture.count"], "label CONTAINS '1 / 30冊'")
        app.buttons["capture.done"].tap()
        XCTAssertTrue(app.buttons["pending.row.0.check"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["pending.heading"].label, "登録待ち 1 / 30冊")
    }
}
