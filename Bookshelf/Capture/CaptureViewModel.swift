import Foundation
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import os

/// 登録待ちの1冊（requirements F1・F2・F3-4）。登録を確定するまではデータベースに入れない
@Observable
final class PendingBook: Identifiable {
    let id = UUID()
    /// 補正済みの表紙（JPEG・メタデータなし）とサムネイル。四隅を直すと入れ替わる（N-041）
    private(set) var image: Data
    private(set) var thumbnail: Data
    private(set) var thumbnailImage: UIImage?
    /// 補正に使った四隅（N 画面で直すときの初期位置。手で合わせた・検出した四隅）
    private(set) var corners: CoverQuad?
    /// 表紙を入れ替えた回数（古い表紙の題名の読み取り結果を捨てるのに使う）
    private(set) var coverRevision = 0
    /// 四隅を直すための元の写真（上向きに縮小した JPEG）。メモリに持たず一時フォルダのファイルに置く（N-034・N-041）
    let sourceFile: PendingSourceFile?
    /// 題名（OCR の先頭の候補が初期値。ユーザーが確認・修正する。F2-1）
    var title = ""
    /// OCR の題名の候補（登録確定までの一時的な値。§10.1）
    var candidates: [String] = []
    var isRecognizing = true
    /// ユーザーが題名欄を触ったら、あとから届いた OCR の候補で上書きしない
    var titleEdited = false
    /// 購入済みにチェック（外すと「買いたい」）。初期値は購入済み（F3-4）
    var owned = true
    /// ジャンル（登録先の棚。買いたい本の棚は選べない）
    var shelf: Shelf

    init(cover: ProcessedCover, shelf: Shelf, source: PendingSourceFile? = nil, corners: CoverQuad? = nil) {
        image = cover.image
        thumbnail = cover.thumbnail
        thumbnailImage = UIImage(data: cover.thumbnail)
        self.corners = cover.corners ?? corners
        sourceFile = source
        self.shelf = shelf
    }

    /// 四隅を直した表紙に入れ替える（N-041）
    func replaceCover(_ cover: ProcessedCover, corners: CoverQuad) {
        image = cover.image
        thumbnail = cover.thumbnail
        thumbnailImage = UIImage(data: cover.thumbnail)
        self.corners = corners
        coverRevision += 1
    }

    var hasTitle: Bool { !LibraryStore.sanitize(title).isEmpty }
}

/// 四隅を検出できなかった1枚、または登録待ちの一覧で四隅を直す1冊（N 画面で手動調整する）。
/// 原寸のデータや展開済みの画像は持たず、上向きに縮小した JPEG だけを持つ（N-034: 30枚選んだときのメモリ）
struct ManualAdjustment: Identifiable {
    let id = UUID()
    /// 上向き・長辺 `PhotoImportHandler.adjustmentLongSide` 以下に縮小した JPEG（メタデータなし）。
    /// 手動の四隅でもう一度 CoverProcessor に通すのも、この画像
    let source: Data
    /// 画面に出す画像。`UIImage(data:)` なので、N 画面に出るまで展開しない
    let preview: UIImage
    /// 登録待ちの一覧から四隅を直すときの、その本の ID（nil なら検出できなかった新しい1枚。N-041）
    let replacing: PendingBook.ID?
    /// N 画面の四隅の初期位置（nil なら各辺から内側に置く）
    let initialCorners: CoverQuad?

    init?(source: Data, replacing: PendingBook.ID? = nil, initialCorners: CoverQuad? = nil) {
        guard let preview = UIImage(data: source) else { return nil }
        self.source = source
        self.preview = preview
        self.replacing = replacing
        self.initialCorners = initialCorners
    }

    var isRecrop: Bool { replacing != nil }
}

/// 登録待ちの本の元の写真（上向きに縮小した JPEG）を置く一時ファイル。使い終わると（本を外す・登録する・閉じる）消える
nonisolated final class PendingSourceFile: Sendable {
    let url: URL
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Capture")

    init?(data: Data) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PendingSource-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            Self.logger.error("元の写真を一時ファイルに書けない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        self.url = url
    }

    func read() -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            Self.logger.error("元の写真の一時ファイルを読めない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    deinit {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("元の写真の一時ファイルを消せない: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// 撮影画像の処理（四隅検出・台形補正・縮小・再エンコード）をメインスレッドの外で順に行う。
/// CoverProcessor（＝CIContext）を1つだけ持ち、撮影のたびに作り直さない（N-009・plan T5）。
/// Vision・Core Image は同期で時間がかかるので、Swift の並行処理用のスレッドをふさがないよう専用のキューで動かす（N-035）
nonisolated final class CoverPipeline: @unchecked Sendable {
    // processor は queue の上だけで使う（直列のキューで1枚ずつ処理する）
    private let processor = CoverProcessor()
    private let queue = DispatchQueue(label: "com.ryutaro3215.bookshelf.cover", qos: .userInitiated)

    /// `fromLibrary` が true で書影の画像そのもの（CoverProcessor.isDigitalCover）なら、四隅を探さず画像全体を使う
    func process(_ data: Data, corners: CoverQuad? = nil, fromLibrary: Bool = false) async throws -> ProcessedCover {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [processor] in
                continuation.resume(
                    with: Result {
                        let whole = fromLibrary && corners == nil && CoverProcessor.isDigitalCover(data)
                        return try processor.process(data, corners: corners, wholeImage: whole)
                    })
            }
        }
    }

    /// 手動調整を待つ間に持っておく、上向きの縮小 JPEG（N 画面の表示と、手動の四隅での補正に使う。N-034）
    func adjustmentSource(_ data: Data) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: PhotoImportHandler.downscaledJPEG(data, longSide: PhotoImportHandler.adjustmentLongSide))
            }
        }
    }
}

/// 「直前に使った棚」の記録（requirements F1-5）。新しい順に棚の ID を持つ
struct RecentShelves {
    static let key = "registration.recentShelves"
    static let maxCount = 10
    let defaults: UserDefaults

    /// 棚を使った（登録先にした・閲覧で開いた）ことを記録する
    func record(_ shelf: Shelf) {
        guard let entry = try? JSONEncoder().encode(shelf.persistentModelID) else { return }
        var list = defaults.array(forKey: Self.key) as? [Data] ?? []
        list.removeAll { $0 == entry }
        list.insert(entry, at: 0)
        defaults.set(Array(list.prefix(Self.maxCount)), forKey: Self.key)
    }

    /// 登録先の初期値: 直前に使った棚。それが買いたい本なら、買いたい本以外で直前に使った棚。なければ未分類
    func initialShelf(in store: LibraryStore) throws -> Shelf {
        let shelves = try store.shelves()
        let list = defaults.array(forKey: Self.key) as? [Data] ?? []
        for entry in list {
            guard let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: entry),
                let shelf = shelves.first(where: { $0.persistentModelID == id })
            else { continue }
            if shelf.kind == .wishlist { continue }
            return shelf
        }
        return try store.unsortedShelf()
    }
}

/// 撮影登録フロー（カメラ → 登録待ちの一覧 → 登録）の状態（plan T5・requirements F1・F2・F3-4）
@Observable
final class CaptureViewModel {
    /// 一度に登録できる冊数の上限（F1-8）
    static let limit = 30

    enum Screen: Equatable {
        case camera
        case pending
    }

    /// 何のための撮影か。`reshoot` は編集画面の「表紙を撮り直す」（1枚だけ撮る。T9）
    enum Purpose: Equatable {
        case registration
        case reshoot
    }

    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Capture")
    /// 撮影ボタン押下 → 次の撮影可能までの時間（実機で Instruments の os_signpost で測る。plan T5: 1秒以内）
    private static let signposter = OSSignposter(subsystem: "com.ryutaro3215.bookshelf", category: "Capture")

    var screen: Screen
    /// 撮影時の登録先（新しく撮った本のジャンルの初期値）
    var destination: Shelf
    private(set) var items: [PendingBook] = []
    /// 撮影済みで処理中の枚数（上限の数に入れる）
    private(set) var processingCount = 0
    /// 四隅を検出できず、手動調整を待っている画像（先頭を N 画面に出す）
    private(set) var adjustments: [ManualAdjustment] = []
    private(set) var isShutterBusy = false
    /// 直前の撮影で表紙を検出できたか（検出の表示に使う）
    private(set) var lastCaptureDetected: Bool?
    /// 撮影した1枚で表紙を検出できたことを、短い間だけ知らせる（ライブの検出が無い間の表示用）
    private(set) var showsDetectedFlash = false
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    var errorMessage: String?
    /// ライブラリから始めたとき、一覧を開いたらすぐ写真ピッカーを出す
    var opensLibraryOnAppear = false
    /// 初回チュートリアルの撮影（L-3）: 1冊も撮っていない間、シャッターの上に「ここを押して撮影」を出し、ほかの操作を隠す（T14）
    var showsShutterHint = false
    /// 最後に測った「撮影 → 次の撮影可能」の時間（ミリ秒。デバッグ表示・ログ用）
    private(set) var lastShutterLatencyMilliseconds: Int?

    let store: LibraryStore
    let camera: any CameraSource
    let purpose: Purpose
    @ObservationIgnored private let pipeline = CoverPipeline()
    @ObservationIgnored private let recognizer = TitleRecognizer()
    @ObservationIgnored private let recent: RecentShelves

    init(
        store: LibraryStore, camera: any CameraSource, destination: Shelf, recent: RecentShelves, screen: Screen,
        purpose: Purpose = .registration
    ) {
        self.store = store
        self.camera = camera
        self.purpose = purpose
        self.destination = destination
        self.recent = recent
        self.screen = screen
    }

    // MARK: - 数（F1-8）

    /// 一度に扱える冊数（登録は30冊。表紙の撮り直しは1枚）
    var capacity: Int { purpose == .reshoot ? 1 : Self.limit }
    /// 上限に数える冊数（登録待ち＋処理中＋手動調整待ち。一覧から四隅を直している本は登録待ちの方で数える）
    var reservedCount: Int { items.count + processingCount + adjustments.filter { !$0.isRecrop }.count }
    var remaining: Int { max(0, capacity - reservedCount) }
    var isAtLimit: Bool { reservedCount >= capacity }
    var canShoot: Bool { !isAtLimit && !isShutterBusy && adjustments.isEmpty }

    var ownedCount: Int { items.filter(\.owned).count }
    var wantedCount: Int { items.count - ownedCount }
    var untitledCount: Int { items.filter { !$0.hasTitle }.count }
    var recognizingUntitledCount: Int { items.filter { !$0.hasTitle && $0.isRecognizing }.count }
    var canRegister: Bool {
        !items.isEmpty && untitledCount == 0 && processingCount == 0 && adjustments.isEmpty
    }

    /// 登録先に選べる棚（買いたい本は本の入れ物ではないので除く。§10.3）
    func selectableShelves() -> [Shelf] {
        do {
            return try store.shelves().filter { $0.kind != .wishlist }
        } catch {
            Self.logger.error("棚の一覧を読めない: \(error.localizedDescription, privacy: .public)")
            return [destination]
        }
    }

    // MARK: - 撮影（F1-1・F1-3）

    func shutter() async {
        guard canShoot else { return }
        isShutterBusy = true
        processingCount += 1
        let state = Self.signposter.beginInterval("ShutterToReady")
        let start = ContinuousClock.now
        do {
            let data = try await camera.capturePhoto()
            isShutterBusy = false
            let elapsed = ContinuousClock.now - start
            Self.signposter.endInterval("ShutterToReady", state)
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            lastShutterLatencyMilliseconds = ms
            Self.logger.info("撮影 → 次の撮影可能: \(ms) ms")
            // 補正・OCR は待たない（F2-2）。撮影ボタンはすでに押せる
            Task { await self.ingest(data) }
        } catch {
            Self.signposter.endInterval("ShutterToReady", state)
            isShutterBusy = false
            processingCount -= 1
            Self.logger.error("撮影に失敗: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(appLocalized: "撮影できませんでした。もう一度お試しください")
        }
    }

    /// 撮影・ライブラリの画像を処理する。四隅を検出できれば登録待ちへ、できなければ手動調整（N 画面）へ。
    /// ライブラリから選んだ書影の画像そのもの（撮影情報が無く表紙の形）は、四隅を探さずそのまま登録待ちへ入れる。
    /// 呼ぶ前に `processingCount` を1つ増やしておくこと（撮影は shutter、ライブラリは reserveImport が増やす）
    func ingest(_ data: Data, fromLibrary: Bool = false) async {
        do {
            let result = try await pipeline.process(data, fromLibrary: fromLibrary)
            if result.isDetected {
                // あとで一覧から四隅を直せるよう、元の写真を縮小して一時ファイルに置く（N-041）
                let source = await pipeline.adjustmentSource(data).flatMap(PendingSourceFile.init(data:))
                processingCount -= 1
                lastCaptureDetected = true
                flashDetected()
                append(result, source: source)
            } else {
                processingCount -= 1
                lastCaptureDetected = false
                guard let source = await pipeline.adjustmentSource(data),
                    let adjustment = ManualAdjustment(source: source)
                else {
                    errorMessage = String(appLocalized: "画像を読み込めませんでした")
                    return
                }
                adjustments.append(adjustment)
            }
        } catch {
            processingCount -= 1
            Self.logger.error("表紙の処理に失敗: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(appLocalized: "画像を読み込めませんでした")
        }
    }

    private func flashDetected() {
        showsDetectedFlash = true
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showsDetectedFlash = false
        }
    }

    /// N 画面: 手動の四隅で補正して登録待ちへ入れる（一覧から直したときは、その本の表紙を入れ替える）
    func confirmAdjustment(_ adjustment: ManualAdjustment, corners: CoverQuad) async {
        do {
            let result = try await pipeline.process(adjustment.source, corners: corners)
            adjustments.removeAll { $0.id == adjustment.id }
            if let id = adjustment.replacing {
                guard let item = items.first(where: { $0.id == id }) else { return }
                item.replaceCover(result, corners: corners)
                recognizeTitle(of: item)
            } else {
                append(result, source: PendingSourceFile(data: adjustment.source), corners: corners)
            }
        } catch {
            Self.logger.error("手動の四隅で補正できない: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(appLocalized: "この範囲では補正できませんでした。角を動かしてもう一度お試しください")
        }
    }

    /// N 画面: 撮り直す（この1枚は捨てる）。一覧から直していたときは、表紙を変えずに閉じる
    func discardAdjustment(_ adjustment: ManualAdjustment) {
        adjustments.removeAll { $0.id == adjustment.id }
    }

    /// 登録待ちの一覧で、本の表紙の四隅を直す（N 画面を開く。N-041）。元の写真が無ければ何もしない
    func beginRecrop(_ item: PendingBook) {
        guard adjustments.isEmpty, let data = item.sourceFile?.read(),
            let adjustment = ManualAdjustment(source: data, replacing: item.id, initialCorners: item.corners)
        else { return }
        adjustments.append(adjustment)
    }

    /// 写真ライブラリで選んだ写真を、撮影と同じ流れで登録待ちへ入れる（F1-4。処理は PhotoImportHandler）
    func importPhotos(_ photos: [some ImportablePhoto]) async {
        await PhotoImportHandler.importPhotos(photos, into: self)
    }

    /// ライブラリで選んだ枚数を、上限の数に先に予約する（読み込み中に撮影しても30冊を超えない。F1-8）。予約できた数を返す
    func reserveImport(_ count: Int) -> Int {
        let accepted = min(max(count, 0), remaining)
        processingCount += accepted
        return accepted
    }

    /// 予約した1枚を読み込めなかったので、予約を戻す
    func releaseImportReservation() {
        processingCount = max(processingCount - 1, 0)
    }

    private func append(_ cover: ProcessedCover, source: PendingSourceFile? = nil, corners: CoverQuad? = nil) {
        let item = PendingBook(cover: cover, shelf: destination, source: source, corners: corners)
        items.append(item)
        recognizeTitle(of: item)
    }

    /// 表紙から題名の候補を読む。題名欄を触っていなければ先頭の候補を入れる。
    /// 四隅を直して読み直したときは、古い表紙の結果が後から届いても使わない
    private func recognizeTitle(of item: PendingBook) {
        let recognizer = recognizer
        let image = item.image
        let revision = item.coverRevision
        item.isRecognizing = true
        // 題名の候補は非同期（F2-2）。@concurrent なのでメインスレッドでは動かない（N-025）
        Task {
            let candidates = await recognizer.candidates(in: image)
            guard item.coverRevision == revision else { return }
            item.candidates = candidates
            if !item.titleEdited, let first = candidates.first {
                item.title = first
            }
            item.isRecognizing = false
        }
    }

    // MARK: - 登録待ちの一覧（F3-4）

    func setAllOwned(_ owned: Bool) {
        for item in items { item.owned = owned }
    }

    func remove(_ item: PendingBook) {
        items.removeAll { $0.id == item.id }
    }

    /// 登録する。購入済みはジャンルの末尾に購入日＝今日で、チェックを外した本は「買いたい」で並ぶ
    @discardableResult
    func register(now: Date = .now) throws -> Int {
        guard canRegister else { return 0 }
        var registered = 0
        for item in items {
            let id = UUID()
            do {
                // 画像の保存も同じ do に入れる。途中で失敗しても、登録済みの本は一覧から外してから投げる（二重登録を防ぐ）
                try store.images.save(original: item.image, thumbnail: item.thumbnail, for: id)
                try store.addBook(
                    title: item.title, shelf: item.shelf, ownership: item.owned ? .owned : .wanted, now: now, id: id)
            } catch {
                do {
                    try store.images.delete(for: id)
                } catch let cleanup {
                    Self.logger.error("登録に失敗した本の画像を消せない: \(cleanup.localizedDescription, privacy: .public)")
                }
                // ここまでに登録した本は一覧から外し、残りはそのまま残す
                items.removeFirst(registered)
                throw error
            }
            registered += 1
        }
        recent.record(destination)
        items.removeAll()
        return registered
    }
}
