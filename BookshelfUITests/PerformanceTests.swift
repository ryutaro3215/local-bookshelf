import XCTest

/// 500冊での非機能要件の計測（plan T12。requirements N1・N2）。
/// 最初に `-UITestPersistentStore -UITestReset -SeedPerf 500` で500冊（表紙は実際の登録と同じ処理を通した JPEG）を
/// ファイルに保存したデータを作り、以降はそのデータで起動して測る。
/// - コールドスタートから棚の表示まで1秒以内（アプリ自身がプロセスの開始から棚に本が出るまでを測り、`perf.probe` で渡す）
/// - XCTApplicationLaunchMetric（起動）・XCTOSSignpostMetric（棚のスクロールのヒッチ）を記録する
/// - 共有画像の生成が3秒以内（共有マークを押してから画像が出るまで。表紙の読み込みを含む）
/// - 500冊のデータ容量が300MB以下（データベースと表紙のフォルダ）
/// 結果は「PERF」で始まる行で標準出力に出す（.dev/perf-report.md に転記する）。シミュレータの値は iPhone 13 の実機の値ではない
@MainActor
final class PerformanceTests: XCTestCase {
    private static var seeded = false
    private static let bookCount = 500

    override func setUp() async throws {
        continueAfterFailure = false
        if !Self.seeded {
            let app = XCUIApplication()
            app.launchArguments =
                UITestLanguage.japanese + [
                    "-UITestPersistentStore", "-UITestReset", "-SeedPerf", "\(Self.bookCount)",
                ]
            app.launch()
            XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 300), "500冊のシードが終わらない")
            app.terminate()
            Self.seeded = true
        }
    }

    // MARK: - 手順

    private func makeApp(probe: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLanguage.japanese + ["-UITestPersistentStore"] + (probe ? ["-PerfProbe"] : [])
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// `perf.probe` の値（「launch=123;bytes=456」）
    private func probe(_ app: XCUIApplication, _ key: String) -> Double? {
        let marker = element(app, "perf.probe")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if marker.exists {
                let pairs = marker.label.split(separator: ";").map { $0.split(separator: "=", maxSplits: 1) }
                if let pair = pairs.first(where: { $0.first.map(String.init) == key }), pair.count == 2,
                    let value = Double(pair[1])
                {
                    return value
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - 起動

    /// コールドスタートから棚の表示まで1秒以内（5回の中央値）
    func testColdStartShowsShelfWithinOneSecond() throws {
        var values: [Double] = []
        for _ in 0..<5 {
            let app = makeApp()
            app.launch()
            XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
            let milliseconds = try XCTUnwrap(probe(app, "launch"), "起動の計測値が出ない")
            values.append(milliseconds)
            app.terminate()
        }
        let middle = median(values)
        print("PERF coldStartToShelf ms=\(values.map { Int($0) }) median=\(Int(middle))")
        XCTAssertLessThan(middle, 1000, "コールドスタートから棚の表示まで: \(values)")
    }

    /// 起動の指標（XCTApplicationLaunchMetric。結果は xcresult とログに出る）
    func testLaunchMetric() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            makeApp(probe: false).launch()
        }
    }

    // MARK: - スクロール

    /// 棚のスクロール（横に本をめくる・縦に棚を変える）のヒッチ（XCTOSSignpostMetric）
    func testShelfScrollingHitches() {
        let app = makeApp(probe: false)
        app.launch()
        let carousel = app.collectionViews["shelf.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            carousel.swipeLeft(velocity: .fast)
            carousel.swipeLeft(velocity: .fast)
            carousel.swipeRight(velocity: .fast)
        }
    }

    // MARK: - 共有画像

    /// 共有画像の生成が3秒以内（小説の棚＝200冊のモザイク。4:5 の縮小と 9:16 のプレビュー）
    func testShareImageWithinThreeSeconds() {
        let app = makeApp(probe: false)
        app.launch()
        let title = app.buttons["shelf.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        if title.label != "小説" {
            title.tap()
            let row = app.buttons["picker.row.小説"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
        let predicate = NSPredicate(format: "label == '小説'")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: title)], timeout: 10),
            .completed)
        print("PERF share shelf=\(title.label) count=\(title.value as? String ?? "")")

        let started = Date()
        app.buttons["shelf.share"].tap()
        XCTAssertTrue(element(app, "share.image").waitForExistence(timeout: 10))
        let portrait = Date().timeIntervalSince(started)

        element(app, "share.destination.story").tap()
        let storyStarted = Date()
        XCTAssertTrue(element(app, "share.preview").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "share.image").waitForExistence(timeout: 10))
        let story = Date().timeIntervalSince(storyStarted)
        print("PERF shareImage portrait=\(String(format: "%.2f", portrait))s story=\(String(format: "%.2f", story))s")
        XCTAssertLessThan(portrait, 3, "4:5 の共有画像が出るまで")
        XCTAssertLessThan(story, 3, "9:16 の共有画像が出るまで")
    }

    // MARK: - データ容量

    /// 500冊のデータ容量が300MB以下
    func testDataSizeUnder300MB() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["shelf.title"].waitForExistence(timeout: 20))
        let bytes = try XCTUnwrap(probe(app, "bytes"), "データ容量の計測値が出ない")
        let megabytes = bytes / 1_000_000
        print("PERF dataSize books=\(Self.bookCount) bytes=\(Int(bytes)) MB=\(String(format: "%.1f", megabytes))")
        XCTAssertLessThanOrEqual(megabytes, 300)
    }
}
