import Foundation
import Testing

@testable import Bookshelf

/// 実写（オーナーの蔵書サンプル）での題名の認識精度の実測（plan.md T4・business-plan 検証方法1）。
/// 実写と正解題名は著作物を含むため git 管理外（design/sample-covers/）。無い環境（CI・クリーンなチェックアウト）ではスキップする。
/// 結果は標準出力に表で出す（題名は出さず、サンプルは番号で示す）。.dev/ocr-accuracy.md に転記する
nonisolated enum OCRSamples {
    /// リポジトリの design/sample-covers（このファイルの位置から辿る。シミュレータからもホストのパスを読める）
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "design/sample-covers")
    static let manifest = directory.appending(path: "manifest.json")
    static let rawTitles = directory.appending(path: "raw-titles.json")
    static let coverCategories = directory.appending(path: "cover-categories.json")

    /// 精度の実測は時間がかかる（約36秒）ため、環境変数 BOOKSHELF_ACCURACY=1 のときだけ動かす（N-026）。
    /// 実行例: `TEST_RUNNER_BOOKSHELF_ACCURACY=1 xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf ...`
    /// （xcodebuild は TEST_RUNNER_ を外した名前でテストに渡す）
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BOOKSHELF_ACCURACY"] == "1"
    }

    static var isAvailable: Bool {
        isEnabled && FileManager.default.fileExists(atPath: manifest.path)
            && FileManager.default.fileExists(atPath: rawTitles.path)
    }
}

/// 1枚のサンプル（番号・画像・正解題名・カテゴリ）
nonisolated struct OCRSample: Sendable {
    var label: String
    var image: URL
    var title: String
    var vertical = false
    var decorative = false
    var obi = false
}

/// 1枚の判定結果
nonisolated struct OCRScore: Sendable {
    var sample: OCRSample
    /// 先頭の候補が正解
    var top1: Bool
    /// 候補のどれかが正解
    var inCandidates: Bool
    /// 候補のどれかが正解の題名を含む（余計な文字を消せば済む。参考値）
    var containsTitle: Bool
}

@Suite(
    .enabled(if: OCRSamples.isAvailable, "BOOKSHELF_ACCURACY=1 でないか、実写のサンプル（design/sample-covers）が無いためスキップ"),
    .serialized)
nonisolated struct OCRAccuracyTests {
    let recognizer = TitleRecognizer()

    func json(_ url: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    /// 切り抜き済み23枚（manifest.json）。カテゴリは cover-categories.json
    func croppedSamples() throws -> [OCRSample] {
        let entries = try #require(try json(OCRSamples.manifest) as? [[String: Any]])
        var flags: [Int: [String: Any]] = [:]
        if let categories = try? json(OCRSamples.coverCategories) as? [String: Any],
            let samples = categories["samples"] as? [[String: Any]]
        {
            for sample in samples {
                if let index = sample["index"] as? Int { flags[index] = sample }
            }
        }
        return try entries.map { entry in
            let index = try #require(entry["index"] as? Int)
            let file = try #require(entry["file"] as? String)
            let title = try #require(entry["title"] as? String)
            let flag = flags[index] ?? [:]
            return OCRSample(
                label: String(format: "C%02d", index), image: OCRSamples.directory.appending(path: file), title: title,
                vertical: flag["vertical"] as? Bool ?? false, decorative: flag["decorative"] as? Bool ?? false,
                obi: flag["obi"] as? Bool ?? false)
        }
    }

    /// 未加工の実写25枚（raw-titles.json）
    func rawSamples() throws -> [OCRSample] {
        let root = try #require(try json(OCRSamples.rawTitles) as? [String: Any])
        let entries = try #require(root["samples"] as? [[String: Any]])
        return try entries.map { entry in
            let number = try #require(entry["number"] as? Int)
            let file = try #require(entry["file"] as? String)
            let title = try #require(entry["title"] as? String)
            return OCRSample(
                label: String(format: "R%02d", number), image: OCRSamples.directory.appending(path: "raw/\(file)"),
                title: title, vertical: entry["vertical"] as? Bool ?? false,
                decorative: entry["decorative"] as? Bool ?? false, obi: entry["obi"] as? Bool ?? false)
        }
    }

    func score(_ sample: OCRSample, candidates: [String]) -> OCRScore {
        let truth = TitleMatch.normalize(sample.title)
        let normalized = candidates.map(TitleMatch.normalize)
        return OCRScore(
            sample: sample, top1: normalized.first == truth, inCandidates: normalized.contains(truth),
            containsTitle: normalized.contains { !truth.isEmpty && $0.contains(truth) })
    }

    /// カテゴリごとの表（Markdown）を標準出力に出す
    func report(_ name: String, _ scores: [OCRScore]) {
        func row(_ category: String, _ filter: (OCRSample) -> Bool) -> String {
            let subset = scores.filter { filter($0.sample) }
            let n = subset.count
            func rate(_ hit: (OCRScore) -> Bool) -> String {
                let count = subset.filter(hit).count
                guard n > 0 else { return "0 / 0 (-)" }
                return "\(count) / \(n) (\(Int((Double(count) / Double(n) * 100).rounded()))%)"
            }
            let note = n < 5 ? " ※5未満" : ""
            let rates = [rate(\.top1), rate(\.inCandidates), rate(\.containsTitle)].joined(separator: " | ")
            return "| \(category) | \(n)\(note) | \(rates) |"
        }
        var lines = [
            "OCR-ACCURACY \(name)",
            "| カテゴリ | サンプル数 | 先頭の候補が正解 | 候補内に正解 | 候補が題名を含む（参考） |",
            "|---|---|---|---|---|",
            row("全体") { _ in true },
            row("縦書き") { $0.vertical },
            row("装飾書体") { $0.decorative },
            row("帯あり") { $0.obi },
            row("いずれにも該当しない") { !$0.vertical && !$0.decorative && !$0.obi },
        ]
        // サンプルごとの判定（番号のみ。T1=先頭が正解 / IN=候補内 / CT=題名を含む / --=不正解）
        lines.append(
            "OCR-SAMPLES \(name): "
                + scores.map { score in
                    let mark = score.top1 ? "T1" : score.inCandidates ? "IN" : score.containsTitle ? "CT" : "--"
                    return "\(score.sample.label)=\(mark)"
                }.joined(separator: " "))
        print(lines.joined(separator: "\n"))
    }

    @Test("切り抜き済みの表紙（manifest.json）で題名の認識精度を測る")
    func croppedCovers() async throws {
        let samples = try croppedSamples()
        #expect(samples.count == 23)
        var scores: [OCRScore] = []
        for sample in samples {
            let candidates = await recognizer.candidates(in: try Data(contentsOf: sample.image))
            scores.append(score(sample, candidates: candidates))
        }
        report("cropped", scores)
    }

    @Test("未加工の実写（raw）を画像パイプライン（四隅検出・補正）に通してから題名の認識精度を測る")
    func rawPhotos() async throws {
        let samples = try rawSamples()
        #expect(samples.count == 25)
        let processor = CoverProcessor()
        var scores: [OCRScore] = []
        var detected = 0
        for sample in samples {
            // アプリと同じ流れ: 撮影画像 → CoverProcessor（検出できなければ元画像全体）→ 文字認識
            let processed = try processor.process(try Data(contentsOf: sample.image))
            if processed.isDetected { detected += 1 }
            let candidates = await recognizer.candidates(in: processed.image)
            scores.append(score(sample, candidates: candidates))
        }
        print("OCR-ACCURACY raw: 四隅を自動検出した枚数 \(detected) / \(samples.count)")
        report("raw", scores)
    }
}
