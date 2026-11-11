import Foundation
import ImageIO
import Testing

@testable import Bookshelf

/// テストバンドル（Fixtures の画像を含む）を探すための目印
private nonisolated final class FixtureBundleToken {}

/// plan.md T3 の acceptance ①〜⑤。フィクスチャは架空の表紙を合成した画像（scripts/generate-cover-fixtures.py）
// T5: 四隅検出に VNDetectDocumentSegmentationRequest を加えたため、同期の検出を並列に多数走らせると
// 協調スレッドが尽きて止まる（CoverDetector.swift の注意を参照）。このスイートは直列に実行する
@Suite(.serialized)
nonisolated struct CoverProcessorTests {
    /// 表紙を斜めから撮った画像（架空の表紙の縦横比は 1:1.45）
    static let coverFixtures = [
        "cover-tilt-left", "cover-tilt-right", "cover-rotated", "cover-top-down-gps",
    ]
    static let coverAspect = 1.45
    /// 合成時に表紙を置いた四隅（ピクセル座標・原点は左上。順に左上・右上・右下・左下。画像は 1536x2048）
    static let truthCorners: [String: [(Double, Double)]] = [
        "cover-tilt-left": [(330, 380), (1220, 300), (1290, 1720), (260, 1610)],
        "cover-tilt-right": [(260, 330), (1150, 420), (1210, 1640), (200, 1760)],
        "cover-rotated": [(420, 260), (1290, 470), (1060, 1780), (170, 1520)],
        "cover-top-down-gps": [(300, 420), (1190, 360), (1250, 1690), (240, 1720)],
    ]
    /// ImageIO の JPEG エンコーダが必ず書く EXIF（画像自身の色空間と大きさ）。元画像由来ではない
    static let encoderExifKeys: Set<String> = [
        kCGImagePropertyExifColorSpace as String,
        kCGImagePropertyExifPixelXDimension as String,
        kCGImagePropertyExifPixelYDimension as String,
    ]

    let processor = CoverProcessor()

    func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: "jpg")
                ?? bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"),
            "フィクスチャ \(name).jpg がテストバンドルにない")
        return try Data(contentsOf: url)
    }

    func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func pixelSize(_ data: Data) throws -> (width: Int, height: Int) {
        let props = try properties(data)
        let width = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    @Test("① フィクスチャ画像で四隅が検出され、出力が表紙の縦横比の矩形になる", arguments: coverFixtures)
    func detectsAndRectifies(name: String) throws {
        let result = try processor.process(try fixture(name))
        let corners = try #require(result.corners, "四隅が検出されなかった")
        #expect(result.isDetected)

        // 検出した四隅が、表紙を置いた位置と一致する（画像の大きさの2%以内）
        let truth = try #require(Self.truthCorners[name])
        let detected = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft]
        for (point, expected) in zip(detected, truth) {
            // Vision の正規化座標（原点は左下）をピクセル座標（原点は左上）の比率に直して比べる
            #expect(abs(Double(point.x) - expected.0 / 1536) < 0.02, "x: \(point) vs \(expected)")
            #expect(abs((1 - Double(point.y)) - expected.1 / 2048) < 0.02, "y: \(point) vs \(expected)")
        }

        // 出力は台形補正後の矩形で、縦長の表紙の比率（1:1.45 前後。透視の推定誤差を見込む）
        let size = try pixelSize(result.image)
        let aspect = Double(size.height) / Double(size.width)
        #expect(abs(aspect - Self.coverAspect) < 0.15, "縦横比 \(aspect)（\(size.width)x\(size.height)）")
    }

    @Test("② 出力の長辺が1600px以下", arguments: coverFixtures + ["no-cover"])
    func longSideIsAtMost1600(name: String) throws {
        let result = try processor.process(try fixture(name))
        let size = try pixelSize(result.image)
        #expect(max(size.width, size.height) <= CoverProcessor.maxLongSide)
        #expect(min(size.width, size.height) > 0)
    }

    @Test("③ サムネイルが生成される", arguments: coverFixtures + ["no-cover"])
    func makesThumbnail(name: String) throws {
        let result = try processor.process(try fixture(name))
        let image = try pixelSize(result.image)
        let thumb = try pixelSize(result.thumbnail)
        #expect(max(thumb.width, thumb.height) == CoverProcessor.thumbnailLongSide)
        // 本体と同じ縦横比
        let ratio = Double(image.height) / Double(image.width)
        let thumbRatio = Double(thumb.height) / Double(thumb.width)
        #expect(abs(ratio - thumbRatio) < 0.02)
    }

    @Test("④ 出力画像に位置情報（GPS）等の EXIF が含まれない", arguments: ["cover-top-down-gps", "no-cover"])
    func stripsMetadata(name: String) throws {
        let input = try fixture(name)
        // 前提: 入力には GPS と EXIF が入っている
        let inputProps = try properties(input)
        #expect(inputProps[kCGImagePropertyGPSDictionary] != nil)
        #expect(inputProps[kCGImagePropertyExifDictionary] != nil)

        let result = try processor.process(input)
        for data in [result.image, result.thumbnail] {
            let props = try properties(data)
            #expect(props[kCGImagePropertyGPSDictionary] == nil)
            // EXIF はエンコーダが書く色空間・大きさのみ（撮影日時・機種・露出などは残らない）
            let exif = props[kCGImagePropertyExifDictionary] as? [String: Any] ?? [:]
            #expect(Set(exif.keys).isSubset(of: Self.encoderExifKeys), "残った EXIF: \(exif.keys)")
            #expect(props[kCGImagePropertyTIFFDictionary] == nil)
            #expect(props[kCGImagePropertyIPTCDictionary] == nil)
        }
    }

    @Test("⑤ 四隅が検出できない画像では元画像を返し、検出失敗を示す")
    func returnsOriginalWhenNotDetected() throws {
        let input = try fixture("no-cover")
        let original = try pixelSize(input)
        let result = try processor.process(input)
        #expect(result.isDetected == false)
        #expect(result.corners == nil)
        // 元画像の全体（縦横比そのまま）を縮小したもの
        let size = try pixelSize(result.image)
        let scale = Double(CoverProcessor.maxLongSide) / Double(max(original.width, original.height))
        #expect(abs(Double(size.width) - Double(original.width) * scale) <= 1)
        #expect(abs(Double(size.height) - Double(original.height) * scale) <= 1)
    }
}
