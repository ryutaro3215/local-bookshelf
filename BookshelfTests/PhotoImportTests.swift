import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit

@testable import Bookshelf

/// 写真ライブラリからの登録（plan T9。requirements F1-4・F1-8・F3・notices N-034）。
/// 写真ピッカー（PhotosPickerItem）はテストで作れないので、合成の画像（架空の題名）を返す写真で代わりに確かめる
@MainActor
struct PhotoImportTests {
    let store: LibraryStore
    let folder: URL

    init() throws {
        let schema = Schema([Book.self, Shelf.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PhotoImportTests-\(UUID().uuidString)", isDirectory: true)
        store = LibraryStore(container: container, images: ImageStore(directory: folder))
        try store.seedIfNeeded()
    }

    func makeModel(destination name: String = "小説") throws -> CaptureViewModel {
        let shelf = try #require(try store.shelves().first { $0.name == name })
        let defaults = try #require(UserDefaults(suiteName: "PhotoImportTests-\(UUID().uuidString)"))
        return CaptureViewModel(
            store: store, camera: FakeCameraSource(), destination: shelf, recent: RecentShelves(defaults: defaults),
            screen: .pending)
    }

    /// 合成の写真（机の上の、少し傾いた表紙）
    static func photo(_ shot: FakeCameraSource.Shot, size: CGSize = CGSize(width: 1536, height: 2048)) -> Data {
        FakeCameraSource.render(shot, size: size).jpegData(compressionQuality: 0.9) ?? Data()
    }

    // MARK: - acceptance

    @Test("写真ライブラリから登録した本: データ追加日は登録日時、購入済みなら購入日の初期値はその日付、買いたいは購入日なし")
    func importedBooksUseRegistrationDate() async throws {
        let model = try makeModel()
        let photos = [
            FakePhoto(Self.photo(.cover("PAPER COMETS"))), FakePhoto(Self.photo(.cover("NORTHERN LANTERNS"))),
        ]
        await model.importPhotos(photos)
        #expect(model.items.count == 2)
        #expect(model.processingCount == 0)
        for (index, item) in model.items.enumerated() {
            item.title = "架空の写真の本 \(index)"
            item.titleEdited = true
        }
        model.items[1].owned = false

        // 写真の撮影日とは関係なく、登録した日時（夜遅くでも購入日はその日の日付）
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 3, 4, 23, 50)
        let now = try #require(Calendar.current.date(from: components))
        #expect(try model.register(now: now) == 2)

        let books = try store.context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(books.count == 2)
        let owned = try #require(books.first { $0.title == "架空の写真の本 0" })
        let wanted = try #require(books.first { $0.title == "架空の写真の本 1" })
        #expect(owned.addedAt == now)
        #expect(owned.ownership == .owned)
        #expect(owned.purchaseDate == Calendar.current.startOfDay(for: now))
        #expect(wanted.addedAt == now)
        #expect(wanted.ownership == .wanted)
        #expect(wanted.purchaseDate == nil)
        #expect(owned.shelf?.name == "小説")
        #expect(wanted.shelf?.name == "小説")
        // 表紙は補正済みの画像として保存されている
        #expect(store.images.loadOriginal(for: owned.id) != nil)
        #expect(store.images.loadThumbnail(for: owned.id) != nil)
    }

    // MARK: - 上限の予約（F1-8）

    @Test("選んだ枚数は登録待ちの残りまで。読めなかった写真の予約は戻る")
    func importRespectsRemainingAndReleasesUnreadable() async throws {
        let model = try makeModel()
        // 27冊分がすでに入っている（撮影の処理中・手動調整待ちと同じ扱いの予約）
        #expect(model.reserveImport(27) == 27)
        #expect(model.remaining == 3)
        let tracker = LoadTracker()
        let photos = [
            FakePhoto(Self.photo(.cover("PAPER COMETS")), tracker: tracker),
            FakePhoto(nil, tracker: tracker),
            FakePhoto(Self.photo(.cover("NORTHERN LANTERNS")), tracker: tracker),
            FakePhoto(Self.photo(.cover("THE QUIET ORCHARD")), tracker: tracker),
            FakePhoto(Self.photo(.cover("PAPER COMETS")), tracker: tracker),
        ]
        let accepted = await PhotoImportHandler.importPhotos(photos, into: model)
        #expect(accepted == 3)
        // 残り3枚のうち、1枚は読めなかったので予約を戻した
        #expect(tracker.loads == 3)
        #expect(model.items.count == 2)
        #expect(model.reservedCount == 29)
        #expect(model.remaining == 1)
        #expect(model.errorMessage == "1枚の写真を読み込めませんでした")
    }

    @Test("読み込みは1枚ずつ（前の写真の処理が終わってから次を読む。N-034）")
    func importLoadsSequentially() async throws {
        let model = try makeModel()
        let tracker = LoadTracker()
        tracker.model = model
        let photos = (0..<3).map { _ in FakePhoto(Self.photo(.cover("PAPER COMETS")), tracker: tracker, delay: true) }
        await model.importPhotos(photos)
        #expect(tracker.loads == 3)
        #expect(tracker.maxConcurrent == 1)
        // 前の写真は、次の写真を読む前に登録待ちに入っている
        #expect(tracker.itemsAtLoad == [0, 1, 2])
        #expect(model.items.count == 3)
    }

    // MARK: - 手動調整待ちのメモリ（N-034）

    @Test("四隅を見つけられない写真は、原寸ではなく上向きに縮小した JPEG だけを持ち、それで補正できる")
    func undetectedPhotoKeepsOnlyDownscaledSource() async throws {
        let model = try makeModel()
        let original = Self.photo(.noCover, size: CGSize(width: 3024, height: 4032))
        await model.importPhotos([FakePhoto(original)])
        #expect(model.items.isEmpty)
        let adjustment = try #require(model.adjustments.first)
        let size = try #require(Self.pixelSize(adjustment.source))
        #expect(Int(max(size.width, size.height)) == PhotoImportHandler.adjustmentLongSide)
        #expect(size.width < size.height)  // 上向きのまま
        #expect(adjustment.source.count < original.count)
        #expect(model.reservedCount == 1)

        await model.confirmAdjustment(adjustment, corners: CoverQuad.inset(0.1))
        #expect(model.adjustments.isEmpty)
        #expect(model.items.count == 1)
    }

    @Test("縮小した画像には元の写真のメタデータ（位置情報）が残らない（S6）")
    func downscaledSourceDropsMetadata() throws {
        let image = FakeCameraSource.render(.noCover, size: CGSize(width: 1200, height: 1600))
        let cg = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 35.0, kCGImagePropertyGPSLongitude: 139.0]
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        #expect(Self.properties(data as Data)?[kCGImagePropertyGPSDictionary] != nil)

        let output = try #require(PhotoImportHandler.downscaledJPEG(data as Data, longSide: 800))
        #expect(Self.properties(output)?[kCGImagePropertyGPSDictionary] == nil)
        #expect(Self.pixelSize(output) == CGSize(width: 600, height: 800))
    }

    // MARK: - 補助

    static func properties(_ data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    static func pixelSize(_ data: Data) -> CGSize? {
        guard let props = properties(data), let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// 読み込みの回数と、同時に読み込んでいる数を数える
@MainActor
final class LoadTracker {
    var loads = 0
    var active = 0
    var maxConcurrent = 0
    /// 読み込みを始めたときの登録待ちの数（モデルを渡したときだけ）
    var itemsAtLoad: [Int] = []
    weak var model: CaptureViewModel?
}

/// テスト用の「写真ピッカーで選んだ1枚」
struct FakePhoto: ImportablePhoto {
    let data: Data?
    var tracker: LoadTracker?
    var delay = false

    init(_ data: Data?, tracker: LoadTracker? = nil, delay: Bool = false) {
        self.data = data
        self.tracker = tracker
        self.delay = delay
    }

    func loadData() async -> Data? {
        guard let tracker else { return data }
        tracker.loads += 1
        tracker.active += 1
        tracker.maxConcurrent = max(tracker.maxConcurrent, tracker.active)
        tracker.itemsAtLoad.append(tracker.model?.items.count ?? -1)
        if delay {
            try? await Task.sleep(for: .milliseconds(20))
        }
        tracker.active -= 1
        return data
    }
}
