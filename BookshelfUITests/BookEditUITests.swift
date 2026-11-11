import XCTest

/// 本の編集・購入した（plan T9 の acceptance ①〜④。E-6・E-7・E-8）。
/// 起動引数 `-UITestReset` でまっさらなデータから始め、`-SeedBooks` で架空の本（合成の表紙）を入れる。
/// 表紙の撮り直しは `-FakeCamera` の合成画像（架空の題名）で「撮影」する
@MainActor
final class BookEditUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    private func launch(seed: String, camera: String = "cover:PAPER COMETS") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-SeedBooks", seed, "-FakeCamera", camera]
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

    private func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }

    private func selectShelf(_ app: XCUIApplication, _ name: String) {
        app.buttons["shelf.title"].tap()
        let row = app.buttons["picker.row.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "棚を選ぶリストに \(name) が無い")
        row.tap()
        wait(app.buttons["shelf.title"], "label == '\(name)'")
    }

    /// 中央の本の詳細を開く
    private func openCenterBook(_ app: XCUIApplication) {
        element(app, "shelf.book.0").tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
    }

    private func openEdit(_ app: XCUIApplication) {
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 5))
    }

    /// 編集画面の行の上下の位置（項目の並びの確認用）
    private func rowOrder(_ app: XCUIApplication, dateID: String) -> [CGFloat] {
        [
            element(app, "edit.title").frame.minY,
            element(app, "edit.genre").frame.minY,
            element(app, "edit.ownership.owned").frame.minY,
            element(app, dateID).frame.minY,
        ]
    }

    // MARK: - ①

    /// 表紙を撮り直して OCR の候補を採用 → 題名を修正 → ジャンルを変える → 保存。詳細と閲覧画面に反映される
    func testAdoptCandidateEditTitleChangeGenreAndSave() {
        let app = launch(seed: "小説:2")
        openCenterBook(app)
        openEdit(app)
        // 今の表紙からの候補（合成の表紙の題名）。読み取りを待つ
        wait(element(app, "edit.titleNote"), "label == '必須'")
        // 表紙を撮り直す（T5 の撮影画面。1枚撮ると編集画面に戻る）
        app.buttons["edit.reshoot"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["capture.library"].exists)
        XCTAssertFalse(app.buttons["capture.done"].exists)
        shutter.tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 20))
        wait(element(app, "edit.cover"), "label == '撮り直した表紙'")
        // 新しい表紙の文字認識の候補を採用する
        let candidate = app.buttons["edit.candidate.0"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 60), "題名の候補が出ない")
        let candidateText = candidate.label.replacingOccurrences(of: "候補 ", with: "")
        XCTAssertTrue(candidateText.uppercased().contains("COMETS"), candidateText)
        candidate.tap()
        let field = app.textFields["edit.title"]
        wait(field, "value == '\(candidateText)'")
        // 修正する（末尾に足す）
        field.tap()
        field.typeText(" 新版")
        wait(field, "value == '\(candidateText) 新版'")
        // ジャンルを変える
        app.buttons["edit.genre"].tap()
        let row = app.buttons["edit.genre.row.エッセイ"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        wait(app.buttons["edit.genre"], "value == 'エッセイ'")
        app.buttons["edit.done"].tap()

        // 詳細に反映され、戻る先はエッセイの棚
        wait(element(app, "detail.title"), "label == '\(candidateText) 新版'")
        XCTAssertTrue(element(app, "detail.genre").label.contains("エッセイ"))
        XCTAssertTrue(element(app, "detail.ownership").label.contains("購入済み"))
        XCTAssertTrue(app.buttons["detail.back"].label.contains("エッセイ"))
        app.buttons["detail.back"].tap()
        wait(app.buttons["shelf.title"], "label == 'エッセイ'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
        XCTAssertEqual(app.staticTexts["shelf.bookTitle"].label, "\(candidateText) 新版")
        // 小説の棚は1冊に減っている
        selectShelf(app, "小説")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
    }

    // MARK: - ②

    /// 「買いたい」にすると購入日は入力できず、「購入済み」に戻すと今日の日付。項目と並びは変わらない
    func testOwnershipSwitchControlsPurchaseDateRow() {
        let app = launch(seed: "小説:1+1")
        openCenterBook(app)
        openEdit(app)
        // E-6（購入済み）
        let date = app.buttons["edit.purchaseDate"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertEqual(date.value as? String, today())
        XCTAssertTrue(app.buttons["edit.ownership.owned"].isSelected)
        let ownedOrder = rowOrder(app, dateID: "edit.purchaseDate")
        XCTAssertEqual(ownedOrder, ownedOrder.sorted())

        app.buttons["edit.ownership.wanted"].tap()
        let disabled = element(app, "edit.purchaseDateDisabled")
        XCTAssertTrue(disabled.waitForExistence(timeout: 5))
        XCTAssertEqual(disabled.value as? String, "購入済みにすると今日の日付が入ります")
        XCTAssertFalse(date.exists)
        XCTAssertTrue(app.buttons["edit.ownership.wanted"].isSelected)
        // 項目の並びは同じ（題名・ジャンル・所持状況・購入日）・同じ位置
        let wantedOrder = rowOrder(app, dateID: "edit.purchaseDateDisabled")
        XCTAssertEqual(wantedOrder, wantedOrder.sorted())
        XCTAssertEqual(Array(wantedOrder.prefix(3)), Array(ownedOrder.prefix(3)))
        XCTAssertTrue(app.buttons["edit.reshoot"].exists)

        app.buttons["edit.ownership.owned"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertEqual(date.value as? String, today())

        // 買いたいで保存すると、詳細は買いたい・購入日なし、戻ると買いたい本の棚
        app.buttons["edit.ownership.wanted"].tap()
        app.buttons["edit.done"].tap()
        XCTAssertTrue(element(app, "detail.ownership").waitForExistence(timeout: 5))
        wait(element(app, "detail.ownership"), "label CONTAINS '買いたい'")
        XCTAssertFalse(element(app, "detail.purchaseDate").exists)
        XCTAssertTrue(element(app, "detail.genre").label.contains("小説"))
        XCTAssertTrue(app.buttons["detail.purchase"].exists)

        // E-7（買いたい本）: 編集を開き直すと購入日の行は入力できない。購入済みにすると今日が入る
        openEdit(app)
        XCTAssertTrue(element(app, "edit.purchaseDateDisabled").waitForExistence(timeout: 5))
        app.buttons["edit.ownership.owned"].tap()
        XCTAssertTrue(app.buttons["edit.purchaseDate"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["edit.purchaseDate"].value as? String, today())
        app.buttons["edit.cancel"].tap()
        wait(element(app, "detail.ownership"), "label CONTAINS '買いたい'")
    }

    // MARK: - ③

    /// 買いたい本の詳細で「購入した」→ ジャンルの棚の末尾に並び購入日は今日。通知の「取り消す」で元に戻る
    func testPurchaseThenUndo() {
        let app = launch(seed: "小説:2+1")
        selectShelf(app, "買いたい本")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
        let wantedTitle = app.staticTexts["shelf.bookTitle"].label
        openCenterBook(app)
        XCTAssertTrue(app.buttons["detail.back"].label.contains("買いたい本"))
        app.buttons["detail.purchase"].tap()

        // E-8: 購入済み・購入日は今日・通知
        wait(element(app, "detail.ownership"), "label CONTAINS '購入済み'")
        XCTAssertTrue(element(app, "detail.purchaseDate").label.contains(today()))
        XCTAssertFalse(app.buttons["detail.purchase"].exists)
        XCTAssertEqual(element(app, "toast.message").label, "購入済みにしました")
        XCTAssertTrue(app.buttons["detail.back"].label.contains("小説"))

        // 取り消す → 買いたいに戻る
        app.buttons["toast.undo"].tap()
        wait(element(app, "detail.ownership"), "label CONTAINS '買いたい'")
        XCTAssertFalse(element(app, "detail.purchaseDate").exists)
        XCTAssertTrue(app.buttons["detail.purchase"].exists)
        XCTAssertTrue(app.buttons["detail.back"].label.contains("買いたい本"))
        app.buttons["detail.back"].tap()
        wait(app.buttons["shelf.title"], "label == '買いたい本'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
        selectShelf(app, "小説")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "2冊")

        // もう一度購入して戻ると、小説の棚の末尾（3冊目）に並んでいる
        selectShelf(app, "買いたい本")
        openCenterBook(app)
        app.buttons["detail.purchase"].tap()
        wait(element(app, "detail.ownership"), "label CONTAINS '購入済み'")
        app.buttons["detail.back"].tap()
        wait(app.buttons["shelf.title"], "label == '小説'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "3冊")
        wait(app.staticTexts["shelf.position"], "label BEGINSWITH '3 / '")
        XCTAssertEqual(app.staticTexts["shelf.bookTitle"].label, wantedTitle)
        XCTAssertTrue(app.staticTexts["shelf.bookMeta"].label.contains(today()))
    }

    // MARK: - ④

    /// 「キャンセル」で変更（題名・ジャンル・所持状況・撮り直した表紙）が破棄される
    func testCancelDiscardsChanges() {
        let app = launch(seed: "小説:1")
        let originalTitle = app.staticTexts["shelf.bookTitle"].label
        openCenterBook(app)
        openEdit(app)
        let field = app.textFields["edit.title"]
        field.tap()
        field.typeText("を書き換え")
        app.buttons["edit.genre"].tap()
        let row = app.buttons["edit.genre.row.歴史"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        wait(app.buttons["edit.genre"], "value == '歴史'")
        app.buttons["edit.ownership.wanted"].tap()
        app.buttons["edit.reshoot"].tap()
        XCTAssertTrue(app.buttons["capture.shutter"].waitForExistence(timeout: 10))
        app.buttons["capture.shutter"].tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 20))
        wait(element(app, "edit.cover"), "label == '撮り直した表紙'")

        app.buttons["edit.cancel"].tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "detail.title").label, originalTitle)
        XCTAssertTrue(element(app, "detail.genre").label.contains("小説"))
        XCTAssertTrue(element(app, "detail.ownership").label.contains("購入済み"))
        XCTAssertTrue(element(app, "detail.purchaseDate").label.contains(today()))
        // 開き直しても元の値
        openEdit(app)
        XCTAssertEqual(app.textFields["edit.title"].value as? String, originalTitle)
        XCTAssertEqual(app.buttons["edit.genre"].value as? String, "小説")
        XCTAssertEqual(element(app, "edit.cover").label, "表紙")
        app.buttons["edit.cancel"].tap()
        app.buttons["detail.back"].tap()
        wait(app.buttons["shelf.title"], "label == '小説'")
        XCTAssertEqual(app.buttons["shelf.title"].value as? String, "1冊")
    }

    // MARK: - C-3（題名の編集。編集画面と同じ入力欄を使う）

    /// 登録待ちの「順に入力する」→ C-3 で1冊ずつ題名を入れ、「次の本へ」で移る。入れた題名は一覧に戻る
    func testPendingTitleEditorFillsTitlesInOrder() {
        let app = launch(seed: "小説:1", camera: "blank,blank")
        app.buttons["browse.add"].tap()
        XCTAssertTrue(app.buttons["register.camera"].waitForExistence(timeout: 5))
        app.buttons["register.camera"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        for _ in 0..<2 {
            wait(shutter, "isEnabled == true", timeout: 20)
            shutter.tap()
        }
        app.buttons["capture.done"].tap()
        let fill = app.buttons["pending.fillNext"]
        XCTAssertTrue(fill.waitForExistence(timeout: 90))
        fill.tap()

        let field = app.textFields["titleEditor.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["titleEditor.position"].label, "1 / 2")
        wait(element(app, "titleEditor.titleNote"), "label == '文字認識の候補なし'", timeout: 30)
        XCTAssertEqual(element(app, "titleEditor.remaining").label, "未入力はこの本を含めてあと2冊")
        field.typeText("架空の一冊目")
        app.buttons["titleEditor.next"].tap()
        wait(app.staticTexts["titleEditor.position"], "label == '2 / 2'")
        XCTAssertEqual(element(app, "titleEditor.remaining").label, "未入力はこの本を含めてあと1冊")
        app.textFields["titleEditor.title"].typeText("架空の二冊目")
        app.buttons["titleEditor.done"].tap()

        XCTAssertTrue(app.textFields["pending.row.0.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["pending.row.0.title"].value as? String, "架空の一冊目")
        XCTAssertEqual(app.textFields["pending.row.1.title"].value as? String, "架空の二冊目")
        wait(app.buttons["pending.register"], "isEnabled == true")
    }
}
