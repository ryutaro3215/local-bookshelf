import CoreGraphics
import Foundation
import Testing

@testable import Bookshelf

/// テストバンドル（Fixtures の画像を含む）を探すための目印
private nonisolated final class OCRFixtureBundleToken {}

/// 題名の一致の判定（.dev/ocr-accuracy.md の「正解」の定義と同じ）。
/// NFKC 正規化（全角英数→半角など）→ 小文字化 → 空白・約物（「」〈〉・、。など）・記号を除く
nonisolated enum TitleMatch {
    static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        let dropped = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { !dropped.contains($0) }))
    }

    static func matches(_ candidate: String, _ truth: String) -> Bool {
        normalize(candidate) == normalize(truth)
    }
}

/// plan.md T4 の acceptance（TitleRecognizerTests）。フィクスチャは架空の表紙（scripts/generate-ocr-fixtures.py）
nonisolated struct TitleRecognizerTests {
    /// フィクスチャ名と、その表紙に描いた架空の題名
    static let titledFixtures: [(name: String, title: String)] = [
        ("ocr-horizontal-en", "PAPER COMETS"),
        ("ocr-horizontal-ja", "架空書店のちいさな地図帳"),  // 2行にわたる題名
        ("ocr-vertical-ja", "星をかぞえる灯台"),  // 縦書き（F2-4）
    ]

    let recognizer = TitleRecognizer()

    func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: OCRFixtureBundleToken.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: "png"), "フィクスチャ \(name).png がテストバンドルにない")
        return try Data(contentsOf: url)
    }

    @Test("① 合成フィクスチャの横書き英語・横書き日本語（と縦書き日本語）で、正解の題名を候補に含む", arguments: titledFixtures)
    func findsTitle(fixture name: String, title: String) async throws {
        let candidates = await recognizer.candidates(in: try fixture(name))
        #expect(candidates.contains { TitleMatch.matches($0, title) }, "候補: \(candidates)")
        #expect(candidates.count <= TitleRecognizer.maxCandidates)
    }

    @Test("① 題名（いちばん大きい文字）が先頭の候補になる", arguments: titledFixtures)
    func titleComesFirst(fixture name: String, title: String) async throws {
        let candidates = await recognizer.candidates(in: try fixture(name))
        let first = try #require(candidates.first)
        #expect(TitleMatch.matches(first, title), "候補: \(candidates)")
    }

    @Test("② 文字のない表紙では空の候補を返す")
    func blankCoverGivesNoCandidates() async throws {
        let candidates = await recognizer.candidates(in: try fixture("ocr-blank"))
        #expect(candidates.isEmpty, "候補: \(candidates)")
    }

    @Test("② 画像として読めないデータでもエラーにせず空の候補を返す")
    func unreadableDataGivesNoCandidates() async {
        #expect(await recognizer.candidates(in: Data()).isEmpty)
        #expect(await recognizer.candidates(in: Data("not an image".utf8)).isEmpty)
    }

    // MARK: - 並べ方（rankCandidates）

    func line(_ text: String, size: Double, x: Double, y: Double, width: Double, height: Double) -> RecognizedLine {
        RecognizedLine(text: text, characterSize: size, frame: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test("2行にわたる題名はつないだものを先に置き、数字・記号だけの行は除く")
    func mergesLinesAndDropsNumbers() {
        let lines = [
            line("定価1540円", size: 20, x: 100, y: 900, width: 200, height: 20),
            line("つづきの行", size: 100, x: 100, y: 230, width: 500, height: 100),
            line("大きな題名の", size: 100, x: 100, y: 100, width: 600, height: 100),
            line("1540", size: 120, x: 100, y: 600, width: 300, height: 120),
            line("著者名", size: 40, x: 100, y: 500, width: 120, height: 40),
        ]
        let candidates = TitleRecognizer.rankCandidates(lines)
        #expect(candidates.first == "大きな題名のつづきの行")
        #expect(candidates.contains("大きな題名の"))
        #expect(!candidates.contains("1540"))
        // 文字の大きい順（題名 → 著者 → 価格）
        #expect(candidates.firstIndex(of: "著者名")! < candidates.firstIndex(of: "定価1540円")!)
    }

    @Test("縦書きの2列は右の列から読む")
    func verticalColumnsReadRightToLeft() {
        let lines = [
            line("左の列", size: 80, x: 300, y: 100, width: 80, height: 300),
            line("右の列", size: 80, x: 420, y: 100, width: 80, height: 300),
        ]
        #expect(TitleRecognizer.rankCandidates(lines).first == "右の列左の列")
    }

    @Test("候補は5件まで・制御文字を除き200文字まで（S6）")
    func candidatesAreLimitedAndCleaned() {
        let lines = (0..<8).map { i in
            line("行\(i)\u{0007}", size: Double(100 - i * 10), x: 0, y: Double(i * 300), width: 100, height: 20)
        }
        let candidates = TitleRecognizer.rankCandidates(lines)
        #expect(candidates == ["行0", "行1", "行2", "行3", "行4"])

        let long = String(repeating: "長", count: 300)
        let clipped = TitleRecognizer.rankCandidates([line(long, size: 10, x: 0, y: 0, width: 900, height: 10)])
        #expect(clipped.first?.count == TitleRecognizer.maxLength)
    }

    @Test("正解の判定は空白・約物・全角半角・大文字小文字の違いを無視する")
    func titleMatchNormalizes() {
        #expect(TitleMatch.matches("星は「なぜ」光るか", "星はなぜ光るか"))
        #expect(TitleMatch.matches("ガラス・ボトルの町", "ガラスボトルの町"))
        #expect(TitleMatch.matches("ＰＡＰＥＲ　Comets", "paper comets"))
        #expect(!TitleMatch.matches("月の", "月の地図"))
    }
}

/// 編集画面で表紙を撮り直したときの題名の読み取り（N-071）。読み取りは偽物（門を開けるまで終わらない）
@MainActor
struct TitleCandidateLoaderTests {
    /// 開けるまで待たせる門
    actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    nonisolated static let oldCover = Data([1])
    nonisolated static let newCover = Data([2])

    @Test("撮り直す前の読み取りが後から終わっても、新しい表紙の候補を上書きしない")
    func staleResultIsDiscarded() async {
        let oldGate = Gate()
        let loader = TitleCandidateLoader { data in
            if data == Self.oldCover {
                await oldGate.wait()
                return ["古い表紙の題名"]
            }
            return ["新しい表紙の題名"]
        }
        let first = loader.start(Self.oldCover)
        #expect(loader.isRecognizing)
        let second = loader.start(Self.newCover)
        await second.value
        #expect(loader.candidates == ["新しい表紙の題名"])
        #expect(!loader.isRecognizing)
        await oldGate.open()
        await first.value
        #expect(loader.candidates == ["新しい表紙の題名"])
        #expect(!loader.isRecognizing)
    }

    @Test("古い読み取りが先に終わっても「読み取り中」を解除せず、最新の読み取りが終わってから解除する")
    func recognizingUntilLatestFinishes() async {
        let oldGate = Gate()
        let newGate = Gate()
        let loader = TitleCandidateLoader { data in
            if data == Self.oldCover {
                await oldGate.wait()
                return ["古い表紙の題名"]
            }
            await newGate.wait()
            return ["新しい表紙の題名"]
        }
        let first = loader.start(Self.oldCover)
        let second = loader.start(Self.newCover)
        await oldGate.open()
        await first.value
        #expect(loader.isRecognizing)
        #expect(loader.candidates.isEmpty)
        await newGate.open()
        await second.value
        #expect(!loader.isRecognizing)
        #expect(loader.candidates == ["新しい表紙の題名"])
    }

    @Test("表紙が無いときは候補なしで読み取りを終える")
    func noCover() async {
        let loader = TitleCandidateLoader { _ in ["使われない"] }
        await loader.start(nil).value
        #expect(!loader.isRecognizing)
        #expect(loader.candidates.isEmpty)
    }
}
