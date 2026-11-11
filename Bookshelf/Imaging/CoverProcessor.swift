import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 表紙画像の処理結果。image・thumbnail は再エンコード済みの JPEG（位置情報等のメタデータなし）
nonisolated struct ProcessedCover: Sendable {
    let image: Data
    let thumbnail: Data
    /// 検出した四隅（入力画像に対する正規化座標）。nil なら検出失敗で、image は元画像を縮小したもの
    let corners: CoverQuad?

    var isDetected: Bool { corners != nil }
}

enum CoverProcessorError: Error {
    case unreadableImage
    case renderFailed
    case encodeFailed
}

/// 撮影画像 → 四隅検出 → 台形補正 → 縮小 → メタデータを除いて JPEG 化 → サムネイル（requirements F1-2・N2・S6）
nonisolated struct CoverProcessor {
    /// 保存する表紙の長辺の上限（N2）
    static let maxLongSide = 1600
    /// 一覧用サムネイルの長辺
    static let thumbnailLongSide = 400
    /// 検出・補正に使う作業画像の長辺の上限（処理時間とメモリを抑える）
    static let workingLongSide = 3200
    static let jpegQuality = 0.85

    var detector = CoverDetector()
    private let context = CIContext()

    /// 画像データ（JPEG・HEIC など）を処理する。corners を渡すとその四隅で補正する（手動調整用）
    func process(_ data: Data, corners manual: CoverQuad? = nil) throws -> ProcessedCover {
        let source = try uprightImage(from: data)
        let corners = try manual ?? detector.detect(in: source)

        var output = CIImage(cgImage: source)
        if let corners {
            let p = corners.pixelPoints(width: source.width, height: source.height)
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = output
            filter.topLeft = p.topLeft
            filter.topRight = p.topRight
            filter.bottomRight = p.bottomRight
            filter.bottomLeft = p.bottomLeft
            guard let corrected = filter.outputImage else { throw CoverProcessorError.renderFailed }
            output = corrected
        }

        let image = try render(output, longSide: Self.maxLongSide)
        let thumbnail = try render(output, longSide: Self.thumbnailLongSide)
        return ProcessedCover(image: try jpeg(image), thumbnail: try jpeg(thumbnail), corners: corners)
    }

    /// 向き（EXIF Orientation）を反映した上向きの画像を作る。大きすぎる画像は作業サイズまで縮める
    private func uprightImage(from data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw CoverProcessorError.unreadableImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), Self.workingLongSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw CoverProcessorError.unreadableImage
        }
        return image
    }

    /// 長辺が longSide 以下になるよう縮小して描画する（拡大はしない）
    private func render(_ image: CIImage, longSide: Int) throws -> CGImage {
        let extent = image.extent.integral
        let long = max(extent.width, extent.height)
        guard long > 0 else { throw CoverProcessorError.renderFailed }
        let scale = min(1, CGFloat(longSide) / long)
        var scaled = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        if scale < 1 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = scaled
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1
            guard let out = lanczos.outputImage else { throw CoverProcessorError.renderFailed }
            scaled = out
        }
        let rect = CGRect(
            x: 0, y: 0,
            width: min(CGFloat(longSide), (extent.width * scale).rounded(.down)),
            height: min(CGFloat(longSide), (extent.height * scale).rounded(.down)))
        guard rect.width >= 1, rect.height >= 1,
            let cg = context.createCGImage(
                scaled, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { throw CoverProcessorError.renderFailed }
        return cg
    }

    /// 新しく JPEG を書き出す。元画像のプロパティ（EXIF・GPS 等）はコピーしない（S6）
    private func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CoverProcessorError.encodeFailed }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CoverProcessorError.encodeFailed }
        return data as Data
    }
}
