import Foundation
import SwiftData
import Testing

@testable import Bookshelf

/// plan.md T2 の acceptance ①〜⑨
@MainActor
struct LibraryStoreTests {
    let folder: URL
    let storeURL: URL
    let images: ImageStore

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("library.store")
        images = ImageStore(directory: folder.appendingPathComponent("Covers", isDirectory: true))
    }

    /// 同じファイルを開く新しい ModelContainer（再起動相当）
    func makeStore() throws -> (LibraryStore, ModelContainer) {
        // LibraryStore がコンテナを保持するので、戻り値のコンテナを捨てても解放されない
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        let store = LibraryStore(container: container, images: images)
        try store.seedIfNeeded()
        return (store, container)
    }

    func genre(_ name: String, _ store: LibraryStore) throws -> Shelf {
        try #require(try store.shelves().first(where: { $0.name == name }))
    }

    @Test("① 本の追加でジャンルの末尾に並ぶ")
    func addAppendsToEnd() throws {
        let (store, _) = try makeStore()
        let philosophy = try genre("哲学・思想", store)
        try store.addBook(title: "存在と時間", shelf: philosophy)
        try store.addBook(title: "世界認識の技術", shelf: philosophy)
        try store.addBook(title: "嫉妬論", shelf: philosophy)
        #expect(store.books(in: philosophy).map(\.title) == ["存在と時間", "世界認識の技術", "嫉妬論"])
    }

    @Test("② ジャンルの削除で中の本が未分類へ移り、本数と所持状況が変わらない")
    func deleteGenreMovesBooksToUnsorted() throws {
        let (store, _) = try makeStore()
        let history = try genre("歴史", store)
        let unsorted = try store.unsortedShelf()
        try store.addBook(title: "既存の未分類の本", shelf: unsorted)
        try store.addBook(title: "帳簿の世界史", shelf: history)
        try store.addBook(title: "ユダヤ人の歴史", shelf: history, ownership: .wanted)
        let totalBefore = try store.context.fetchCount(FetchDescriptor<Book>())

        try store.deleteShelf(history)

        #expect(try store.shelves().contains(where: { $0.name == "歴史" }) == false)
        #expect(try store.context.fetchCount(FetchDescriptor<Book>()) == totalBefore)
        let moved = unsorted.books.sorted { $0.sortOrder < $1.sortOrder }
        #expect(moved.map(\.title) == ["既存の未分類の本", "帳簿の世界史", "ユダヤ人の歴史"])
        #expect(moved.first(where: { $0.title == "帳簿の世界史" })?.ownership == .owned)
        #expect(moved.first(where: { $0.title == "ユダヤ人の歴史" })?.ownership == .wanted)
    }

    @Test("③ 買いたい本・未分類は削除も名前変更もできない")
    func systemShelvesAreProtected() throws {
        let (store, _) = try makeStore()
        let wishlist = try #require(try store.wishlistShelf())
        let unsorted = try store.unsortedShelf()
        for shelf in [wishlist, unsorted] {
            #expect(throws: LibraryError.systemShelfIsProtected) { try store.deleteShelf(shelf) }
            #expect(throws: LibraryError.systemShelfIsProtected) { try store.renameShelf(shelf, to: "別の名前") }
        }
        #expect(wishlist.name == "買いたい本")
        #expect(unsorted.name == "未分類")
    }

    @Test("④ 本の削除で画像ファイル（原寸・サムネ）も消える")
    func deleteBookRemovesImages() throws {
        let (store, _) = try makeStore()
        let book = try store.addBook(title: "嫉妬論", shelf: try genre("哲学・思想", store))
        try images.save(original: Data([1, 2, 3]), thumbnail: Data([4, 5]), for: book.id)
        let original = images.originalURL(for: book.id)
        let thumbnail = images.thumbnailURL(for: book.id)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: thumbnail.path))

        try store.deleteBook(book)

        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: thumbnail.path))
        #expect(try store.context.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test("⑤ 題名・ジャンル名が200文字に切り詰められ制御文字が除去される（S6）")
    func namesAreSanitized() throws {
        let (store, _) = try makeStore()
        let longTitle = String(repeating: "あ", count: 250)
        let book = try store.addBook(title: "存在\u{0007}と\n時間\u{0000}", shelf: try genre("哲学・思想", store))
        #expect(book.title == "存在と時間")
        let long = try store.addBook(title: longTitle, shelf: nil)
        #expect(long.title.count == 200)

        let shelf = try store.addGenre(name: "村上\u{001B}春樹" + String(repeating: "x", count: 300))
        #expect(shelf.name.count == 200)
        #expect(shelf.name.hasPrefix("村上春樹"))
        #expect(throws: LibraryError.emptyName) { try store.addBook(title: "\u{0001}\n ", shelf: nil) }
    }

    @Test("⑥ 新しい ModelContainer（再起動相当）後もデータと並び順が保たれる")
    func dataPersistsAcrossContainers() throws {
        do {
            let (store, _) = try makeStore()
            let philosophy = try genre("哲学・思想", store)
            try store.addBook(title: "一", shelf: philosophy)
            try store.addBook(title: "二", shelf: philosophy)
            try store.addBook(title: "三", shelf: philosophy, ownership: .wanted)
            try store.addGenre(name: "村上春樹")
        }
        let (store, _) = try makeStore()
        let philosophy = try genre("哲学・思想", store)
        #expect(store.books(in: philosophy).map(\.title) == ["一", "二"])
        #expect(try store.wishlistBooks().map(\.title) == ["三"])
        let names = try store.shelves().map(\.name)
        #expect(names.count == InitialGenres.genres.count + 3)
        #expect(Array(names.suffix(3)) == ["村上春樹", "買いたい本", "未分類"])
    }

    @Test("⑦ 所持状況を「買いたい」にすると購入日が消え、「購入済み」にすると今日になる（ジャンルは変わらない）")
    func ownershipChangesPurchaseDate() throws {
        let (store, _) = try makeStore()
        let philosophy = try genre("哲学・思想", store)
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        let book = try store.addBook(title: "嫉妬論", shelf: philosophy, now: past)
        #expect(book.purchaseDate == Calendar.current.startOfDay(for: past))

        try store.setOwnership(book, to: .wanted)
        #expect(book.purchaseDate == nil)
        #expect(book.shelf?.name == "哲学・思想")

        let today = Date.now
        try store.setOwnership(book, to: .owned, now: today)
        #expect(book.purchaseDate == Calendar.current.startOfDay(for: today))
        #expect(book.shelf?.name == "哲学・思想")
    }

    @Test("⑧ ジャンル別の一覧に「買いたい」の本が含まれず、買いたい本の一覧にだけ含まれる")
    func wantedBooksOnlyInWishlist() throws {
        let (store, _) = try makeStore()
        let philosophy = try genre("哲学・思想", store)
        try store.addBook(title: "持っている本", shelf: philosophy)
        try store.addBook(title: "買いたい本の一冊", shelf: philosophy, ownership: .wanted)
        #expect(store.books(in: philosophy).map(\.title) == ["持っている本"])
        #expect(try store.wishlistBooks().map(\.title) == ["買いたい本の一冊"])
        let wishlist = try #require(try store.wishlistShelf())
        #expect(throws: LibraryError.invalidShelfForBook) { try store.addBook(title: "x", shelf: wishlist) }
    }

    @Test("⑨ 初回起動で初期ジャンルが区分付き・ja/en 名付きで作られる")
    func initialGenresAreSeeded() throws {
        let (store, _) = try makeStore()
        try store.seedIfNeeded()  // 2回目は何もしない
        let shelves = try store.shelves()
        #expect(shelves.count == 30)
        let genres = shelves.filter { $0.kind == .genre }
        #expect(genres.count == 28)
        #expect(genres.allSatisfy { $0.nameEn?.isEmpty == false })
        let philosophy = try #require(genres.first(where: { $0.name == "哲学・思想" }))
        #expect(philosophy.nameEn == "Philosophy")
        #expect(philosophy.categoryID == InitialGenres.humanities.id)
        #expect(genres.first?.name == "小説")
        #expect(shelves.suffix(2).map(\.kind) == [.wishlist, .unsorted])
        #expect(shelves.suffix(2).map(\.nameEn) == ["Wishlist", "Unsorted"])
        #expect(shelves.suffix(2).allSatisfy { $0.categoryID == InitialGenres.system.id })
        #expect(InitialGenres.system.name == "その他")
    }

    // MARK: - T9: 本の編集・購入した（F6-4・§10.3）

    func day(_ y: Int, _ m: Int, _ d: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: y, month: m, day: d)))
    }

    func cover(_ byte: UInt8) -> ProcessedCover {
        ProcessedCover(image: Data([byte, byte]), thumbnail: Data([byte]), corners: nil)
    }

    @Test("T9 編集: 題名（S6）・ジャンル（移した先の末尾）・購入日を保存する")
    func editTitleGenreAndDate() throws {
        let (store, _) = try makeStore()
        let novel = try genre("小説", store)
        let essay = try genre("エッセイ", store)
        let book = try store.addBook(title: "灰色の標本箱", shelf: novel)
        try store.addBook(title: "遠い観測所", shelf: essay)
        let date = try day(2026, 1, 15)
        try store.updateBook(
            book, with: BookEdit(title: "  灰色の標本箱の記録\u{0007}  ", shelf: essay, ownership: .owned, purchaseDate: date))
        #expect(book.title == "灰色の標本箱の記録")
        #expect(book.yomi == Yomi.make(from: "灰色の標本箱の記録"))
        #expect(store.books(in: essay).map(\.title) == ["遠い観測所", "灰色の標本箱の記録"])
        #expect(store.books(in: novel).isEmpty)
        #expect(book.purchaseDate == date)
        #expect(throws: LibraryError.emptyName) {
            try store.updateBook(book, with: BookEdit(title: " \n ", shelf: essay, ownership: .owned))
        }
        #expect(book.title == "灰色の標本箱の記録")
    }

    @Test("T9 編集: 「買いたい」にすると購入日が消えジャンルは残る。「購入済み」にするとジャンルの末尾に並ぶ")
    func editOwnership() throws {
        let (store, _) = try makeStore()
        let novel = try genre("小説", store)
        let wanted = try store.addBook(title: "静かな温室", shelf: novel, ownership: .wanted)
        try store.addBook(title: "白い回廊", shelf: novel)
        try store.addBook(title: "冬の地図", shelf: novel)
        let today = Calendar.current.startOfDay(for: .now)
        try store.updateBook(
            wanted, with: BookEdit(title: wanted.title, shelf: novel, ownership: .owned, purchaseDate: today))
        #expect(store.books(in: novel).map(\.title) == ["白い回廊", "冬の地図", "静かな温室"])
        #expect(wanted.purchaseDate == today)

        let owned = try #require(store.books(in: novel).first)
        try store.updateBook(owned, with: BookEdit(title: owned.title, shelf: novel, ownership: .wanted))
        #expect(owned.ownership == .wanted)
        #expect(owned.purchaseDate == nil)
        #expect(owned.shelf?.name == "小説")
        #expect(try store.wishlistBooks().map(\.title) == ["白い回廊"])
        #expect(throws: LibraryError.invalidShelfForBook) {
            try store.updateBook(
                owned,
                with: BookEdit(title: owned.title, shelf: try #require(try store.wishlistShelf()), ownership: .wanted))
        }
    }

    @Test("T9 編集: 撮り直した表紙は保存できてから入れ替える。失敗したら古い表紙のまま・仮のファイルを残さない")
    func editReplacesCoverOnlyAfterSave() throws {
        let (store, _) = try makeStore()
        let novel = try genre("小説", store)
        let id = UUID()
        try store.images.save(original: Data([1, 1]), thumbnail: Data([1]), for: id)
        let book = try store.addBook(title: "小さな郵便局", shelf: novel, id: id)

        // 題名が空で保存できない → 表紙は古いまま、仮のファイルも無い
        #expect(throws: LibraryError.emptyName) {
            try store.updateBook(book, with: BookEdit(title: "", shelf: novel, ownership: .owned), newCover: cover(9))
        }
        #expect(store.images.loadOriginal(for: id) == Data([1, 1]))
        let files = try FileManager.default.contentsOfDirectory(atPath: store.images.directory.path)
        #expect(files.count == 2)

        try store.updateBook(
            book, with: BookEdit(title: "小さな郵便局", shelf: novel, ownership: .owned), newCover: cover(2))
        #expect(store.images.loadOriginal(for: id) == Data([2, 2]))
        #expect(store.images.loadThumbnail(for: id) == Data([2]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.images.directory.path).count == 2)
    }

    @Test("T9 購入した: そのジャンルの末尾に並び購入日は今日。取り消すと所持状況・購入日・位置が元に戻る")
    func purchaseAndUndo() throws {
        let (store, _) = try makeStore()
        let novel = try genre("小説", store)
        try store.addBook(title: "青い時計", shelf: novel)
        let book = try store.addBook(title: "眠る鯨", shelf: novel, ownership: .wanted)
        try store.addBook(title: "古い灯台", shelf: novel)
        let before = book.sortOrder
        let record = try store.purchase(book)
        #expect(book.ownership == .owned)
        #expect(book.purchaseDate == Calendar.current.startOfDay(for: .now))
        #expect(store.books(in: novel).map(\.title) == ["青い時計", "古い灯台", "眠る鯨"])
        #expect(try store.wishlistBooks().isEmpty)

        try store.undoPurchase(record)
        #expect(book.ownership == .wanted)
        #expect(book.purchaseDate == nil)
        #expect(book.sortOrder == before)
        #expect(book.shelf?.name == "小説")
        #expect(store.books(in: novel).map(\.title) == ["青い時計", "古い灯台"])
        #expect(try store.wishlistBooks().map(\.title) == ["眠る鯨"])
    }

    @Test("T9 購入した: 本を削除したあとの取り消しは何も変えずに失敗する（N-060 と同じ守り）")
    func undoPurchaseAfterDeleteFailsSafely() throws {
        let (store, _) = try makeStore()
        let novel = try genre("小説", store)
        let other = try store.addBook(title: "長い植物園", shelf: novel)
        let book = try store.addBook(title: "四角い惑星", shelf: novel, ownership: .wanted)
        let record = try store.purchase(book)
        try store.deleteBook(book)
        let orderBefore = other.sortOrder
        #expect(throws: LibraryError.bookNotFound) { try store.undoPurchase(record) }
        #expect(other.sortOrder == orderBefore)
        #expect(store.books(in: novel).map(\.title) == ["長い植物園"])

        // 元のジャンルが削除されていたら、取り消しは shelfNotFound（本は未分類に残る）
        let essay = try genre("エッセイ", store)
        let wanted = try store.addBook(title: "夜更けの書架", shelf: essay, ownership: .wanted)
        let record2 = try store.purchase(wanted)
        try store.deleteShelf(essay)
        #expect(throws: LibraryError.shelfNotFound) { try store.undoPurchase(record2) }
        #expect(wanted.ownership == .owned)
        #expect(wanted.shelf?.kind == .unsorted)
    }
}
