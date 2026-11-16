import XCTest

/// 初回チュートリアルの UI テスト（plan T14 の acceptance ①〜③。requirements F1-7）。
/// ほかの UI テストではチュートリアルを飛ばしているので、ここでは起動引数 `-UITestOnboarding` を付けて出す。
/// `-UITestPersistentStore` で一時フォルダにデータと設定を保存し、再起動しても同じものを開く（③の確認用）。
/// カメラは `-FakeCamera` の架空の表紙の合成画像（実在の本は使わない）
@MainActor
final class OnboardingUITests: XCTestCase {
    private let cover = "cover:PAPER COMETS"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - 手順

    /// - Parameter reset: まっさらなデータ・設定から始める（初回起動）
    private func launch(reset: Bool, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLanguage.japanese + ["-UITestPersistentStore", "-UITestOnboarding", "-FakeCamera", cover]
            + (reset ? ["-UITestReset"] : []) + extra
        app.launch()
        return app
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 20) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element): \(predicate)")
    }

    /// L-1 → L-2 で棚を選び、「○○ で撮影する」を押す
    private func chooseShelf(_ app: XCUIApplication, _ name: String) {
        let start = app.buttons["onboarding.start"]
        if start.exists {
            start.tap()
        }
        XCTAssertTrue(app.staticTexts["onboarding.shelf.heading"].waitForExistence(timeout: 5))
        let row = app.buttons["onboarding.shelf.row.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "L-2 に \(name) が無い")
        row.tap()
        let confirm = app.buttons["onboarding.shelf.confirm"]
        XCTAssertEqual(confirm.label, "\(name) で撮影する")
        confirm.tap()
    }

    /// 案内つきの撮影画面（L-3）で1冊撮り、登録待ちの一覧で題名を確かめて登録する
    private func shootAndRegister(_ app: XCUIApplication) {
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        // L-3: シャッターの案内だけを出し、ライブラリ・完了は出さない
        XCTAssertTrue(app.descendants(matching: .any)["capture.shutterHint"].exists)
        XCTAssertFalse(app.buttons["capture.library"].exists)
        XCTAssertFalse(app.buttons["capture.done"].exists)
        wait(shutter, "isEnabled == true")
        shutter.tap()
        // 1冊撮ると、題名を確かめる一覧へ進む
        let field = app.textFields["pending.row.0.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        wait(app.staticTexts["題名を読み取り中…"], "exists == false", timeout: 90)
        let value = field.value as? String ?? ""
        if value.isEmpty || value == "題名を入力" {
            field.tap()
            field.typeText("Fictional Book")
            app.staticTexts["pending.heading"].tap()
        }
        let register = app.buttons["pending.register"]
        wait(register, "isEnabled == true")
        register.tap()
    }

    private func assertShelf(_ app: XCUIApplication, _ name: String, count: Int) {
        let title = app.buttons["shelf.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        wait(title, "label == '\(name)'")
        wait(title, "value == '\(count)冊'")
    }

    // MARK: - ①②③

    /// ①初回はチュートリアルが出て、1冊登録するまで閲覧画面に進めない ②登録後は閲覧画面に1冊並ぶ ③再起動では出ない
    func testFirstLaunchRequiresFirstBookAndIsShownOnlyOnce() {
        let app = launch(reset: true)
        // ① L-1 ようこそ。閲覧画面（下部バーの＋）は出ていない
        XCTAssertTrue(app.staticTexts["onboarding.welcome"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["onboarding.dots"].value as? String, "1 / 3")
        XCTAssertFalse(app.buttons["browse.add"].exists)
        XCTAssertFalse(app.buttons["shelf.title"].exists)

        // 撮らずにカメラを閉じても、チュートリアルからは抜けない（L-2 に戻る）
        chooseShelf(app, "哲学・思想")
        let close = app.buttons["capture.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.staticTexts["onboarding.shelf.heading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browse.add"].exists)

        // 登録待ちの一覧を登録せずに閉じても、チュートリアルからは抜けない
        app.buttons["onboarding.shelf.row.哲学・思想"].tap()
        app.buttons["onboarding.shelf.confirm"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        wait(shutter, "isEnabled == true")
        shutter.tap()
        XCTAssertTrue(app.buttons["pending.close"].waitForExistence(timeout: 30))
        app.buttons["pending.close"].tap()
        app.buttons["登録せずに閉じる"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.shelf.heading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browse.add"].exists)

        // ② 1冊登録すると、閲覧画面にその1冊が並び、L-4 のシートが出る
        chooseShelf(app, "哲学・思想")
        shootAndRegister(app)
        XCTAssertTrue(app.staticTexts["firstBook.heading"].waitForExistence(timeout: 10))
        app.buttons["firstBook.browse"].tap()
        XCTAssertTrue(app.buttons["browse.add"].waitForExistence(timeout: 10))
        assertShelf(app, "哲学・思想", count: 1)

        // ③ 2回目の起動ではチュートリアルが出ず、1冊が残っている
        app.terminate()
        let relaunched = launch(reset: false)
        XCTAssertTrue(relaunched.buttons["browse.add"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.staticTexts["onboarding.welcome"].exists)
        XCTAssertFalse(relaunched.staticTexts["firstBook.heading"].exists)
        assertShelf(relaunched, "哲学・思想", count: 1)
    }

    /// 登録の前にアプリを閉じたら、次の起動でもチュートリアルから始まる（登録は必須）
    func testRelaunchBeforeRegistrationShowsTutorialAgain() {
        let app = launch(reset: true)
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.shelf.heading"].waitForExistence(timeout: 5))
        app.terminate()

        let relaunched = launch(reset: false)
        XCTAssertTrue(relaunched.staticTexts["onboarding.welcome"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.buttons["browse.add"].exists)
    }

    /// L-2 の初期値は未分類。カメラの許可をまだ聞いていないときは O-1 を出し、許可すると案内つきの撮影へ進む。
    /// L-4 の「続けて登録する」で、選んだ棚を登録先にカメラが開く
    func testCameraPermissionPageAndContinueRegistering() {
        let app = launch(reset: true, extra: ["-UITestCameraPermission"])
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        app.buttons["onboarding.start"].tap()
        let confirm = app.buttons["onboarding.shelf.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "未分類 で撮影する")
        XCTAssertEqual(app.descendants(matching: .any)["onboarding.dots"].value as? String, "2 / 3")

        chooseShelf(app, "歴史")
        // O-1
        XCTAssertTrue(app.staticTexts["onboarding.permission.heading"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["onboarding.dots"].value as? String, "3 / 3")
        XCTAssertTrue(app.buttons["onboarding.permission.library"].exists)
        app.buttons["onboarding.permission.allow"].tap()
        XCTAssertEqual(
            app.buttons["register.destination"].waitForExistence(timeout: 10)
                ? app.buttons["register.destination"].value as? String : nil, "歴史")
        shootAndRegister(app)

        // L-4 →「続けて登録する」でカメラ（登録先は歴史。案内は出さない）
        XCTAssertTrue(app.buttons["firstBook.continue"].waitForExistence(timeout: 10))
        app.buttons["firstBook.continue"].tap()
        XCTAssertTrue(app.buttons["capture.shutter"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["register.destination"].value as? String, "歴史")
        XCTAssertFalse(app.descendants(matching: .any)["capture.shutterHint"].exists)
        XCTAssertTrue(app.buttons["capture.done"].exists)
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["browse.add"].waitForExistence(timeout: 10))
        assertShelf(app, "歴史", count: 1)
    }
}
