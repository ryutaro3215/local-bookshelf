import Foundation
import ImageIO
import Testing

@testable import Bookshelf

/// 実写（未加工の25枚・design/sample-covers/raw）での表紙の四隅の自動検出率の実測（plan.md T5・F1-2）。
/// 実写は著作物のため git 管理外。BOOKSHELF_ACCURACY=1 で、かつ実写がある環境だけで動く（OCRAccuracyTests と同じ条件）。
///
/// 正誤（表紙の四隅を正しく取れたか。表紙の内側の枠や隣の本を取ったものは失敗）はテストでは判定できないため、
/// 環境変数 BOOKSHELF_ACCURACY_OUT にフォルダを指定すると、補正後の表紙を `Rxx.jpg` として書き出す。
/// それを目で見て数え、build-log に記録する。
///
/// 実行例:
/// `TEST_RUNNER_BOOKSHELF_ACCURACY=1 TEST_RUNNER_BOOKSHELF_ACCURACY_OUT=/tmp/crops xcodebuild test ...
///  -only-testing:BookshelfTests/CoverDetectionAccuracyTests`
@Suite(
    .enabled(if: OCRSamples.isAvailable, "BOOKSHELF_ACCURACY=1 でないか、実写のサンプル（design/sample-covers）が無いためスキップ"),
    .serialized)
nonisolated struct CoverDetectionAccuracyTests {
    @Test("未加工の実写25枚で四隅を自動検出できた枚数を数え、補正後の表紙を書き出す")
    func rawPhotos() throws {
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: OCRSamples.rawTitles)) as? [String: Any])
        let entries = try #require(root["samples"] as? [[String: Any]])
        #expect(entries.count == 25)

        let output = ProcessInfo.processInfo.environment["BOOKSHELF_ACCURACY_OUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let output {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        }

        // 連続撮影と同じく、1つの CoverProcessor（＝1つの CIContext）を使い回す
        let processor = CoverProcessor()
        var detected: [String] = []
        var missed: [String] = []
        for entry in entries {
            let number = try #require(entry["number"] as? Int)
            let file = try #require(entry["file"] as? String)
            let label = String(format: "R%02d", number)
            let data = try Data(contentsOf: OCRSamples.directory.appending(path: "raw/\(file)"))
            let result = try processor.process(data)
            if result.isDetected {
                detected.append(label)
            } else {
                missed.append(label)
            }
            if let output {
                try result.image.write(to: output.appending(path: "\(label)\(result.isDetected ? "" : "-miss").jpg"))
            }
        }
        print("COVER-DETECTION raw: 自動検出 \(detected.count) / \(entries.count)")
        print("COVER-DETECTION detected: \(detected.joined(separator: " "))")
        print("COVER-DETECTION missed: \(missed.joined(separator: " "))")
        // 正誤は目視で判定して build-log に記録する（閾値で落とさない）。
        // 注意: iOS シミュレータの VNDetectDocumentSegmentationRequest は画像によらず下端の帯を返す
        // （2026-11 時点・iOS 26.5 シミュレータで確認）ため、シミュレータの数字は実機より低く出る。実機または Mac で測る
        #expect(detected.count + missed.count == entries.count)
    }
}
