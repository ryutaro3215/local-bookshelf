import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import os

/// 写真ピッカーで選んだ1枚。データは読み込むときに初めて取り出す（テストでは合成画像を返すものを使う）
protocol ImportablePhoto {
    /// 画像のデータ（JPEG・HEIC など）。読めなければ nil
    func loadData() async -> Data?
}

extension PhotosPickerItem: ImportablePhoto {
    func loadData() async -> Data? {
        await PhotoLoader.load(self)
    }
}

/// 写真ライブラリからの登録（requirements F1-4・F1-8・S4。plan T9。notices N-034）。
/// - 写真は OS の写真ピッカー（PhotosPicker）で選ぶ。ライブラリの読み取り権限は求めない（Info.plist に用途説明を置かない）
/// - 選んだ時点で、枚数分（登録待ちの残りまで）を上限の数に予約する（読み込み中に撮影しても30冊を超えない）
/// - 1枚ずつ順に読み込み、補正が終わってから次を読む。原寸のデータは処理が終われば手放す
/// - 四隅を見つけられなかった写真は、上向きに縮小した JPEG だけを手動調整待ちとして持つ（原寸・展開済みの画像は持たない）
/// - 登録の確定は撮影と同じ `CaptureViewModel.register`（データ追加日＝登録した日時、購入済みなら購入日＝その日付。F3）
@MainActor
enum PhotoImportHandler {
    /// 手動調整を待つ写真の長辺（保存する表紙の長辺 1600 より大きくし、表紙の部分を切り抜いても粗くなりにくくする）
    nonisolated static let adjustmentLongSide = 2400
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "PhotoImport")

    /// 選んだ写真を、選んだ順に登録待ちへ入れる。受け付けた枚数を返す（残りを超えた分は捨てる）
    @discardableResult
    static func importPhotos(_ photos: [some ImportablePhoto], into model: CaptureViewModel) async -> Int {
        let accepted = model.reserveImport(photos.count)
        if accepted < photos.count {
            logger.info("上限を超えた \(photos.count - accepted) 枚は登録待ちに入れない")
        }
        var unreadable = 0
        for photo in photos.prefix(accepted) {
            // 1枚ずつ: 読み込み → 補正（ingest の中で処理が終わるまで待つ）→ 次の写真
            guard let data = await photo.loadData() else {
                model.releaseImportReservation()
                unreadable += 1
                continue
            }
            await model.ingest(data)
        }
        if unreadable > 0 {
            model.errorMessage = "\(unreadable)枚の写真を読み込めませんでした"
        }
        return accepted
    }

    /// 向き（EXIF Orientation）を反映し、長辺を `longSide` 以下にした JPEG を作る。
    /// 新しく書き出すので、元の写真のメタデータ（位置情報など）は残らない（S6）
    nonisolated static func downscaledJPEG(_ data: Data, longSide: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: CoverProcessor.jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// 写真ピッカーで選んだ写真のデータを読む（読めない写真は nil を返してログに残す）
enum PhotoLoader {
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "PhotoLoader")

    static func load(_ item: PhotosPickerItem) async -> Data? {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                return data
            }
            logger.error("写真のデータが空")
        } catch {
            logger.error("写真を読めない: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
}
