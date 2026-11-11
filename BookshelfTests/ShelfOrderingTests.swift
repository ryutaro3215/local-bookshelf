import Foundation
import SwiftData
import Testing

@testable import Bookshelf

/// plan.md T7 の acceptance（ShelfOrderingTests）: 1冊の移動・棚間移動・購入日の新しい順/古い順・
/// データ追加日の新しい順/古い順・題名順はよみで並ぶ。題名はすべて架空のもの
@MainActor
struct ShelfOrderingTests {
    let folder: URL
    let images: ImageStore
    let store: LibraryStore
    /// 2026-01-01 00:00（UTC）
    let base = Date(timeIntervalSince1970: 1_767_225_600)

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ShelfOrderingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        images = ImageStore(directory: folder.appendingPathComponent("Covers", isDirectory: true))
        let config = ModelConfiguration(url: folder.appendingPathComponent("library.store"))
        let container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        store = LibraryStore(container: container, images: images)
        try store.seedIfNeeded()
    }

    func genre(_ name: String) throws -> Shelf {
        try #require(try store.shelves().first(where: { $0.name == name }))
    }

    func day(_ n: Int) -> Date {
        base.addingTimeInterval(Double(n) * 86_400)
    }

    func titles(_ shelf: Shelf) -> [String] {
        store.books(in: shelf).map(\.title)
    }

    /// 架空の本を4冊（データ追加日と購入日がばらばらになるように）入れる
    func seedFour(_ shelf: Shelf) throws -> [Book] {
        // 追加した順: A, B, C, D。データ追加日: A=1日, B=3日, C=2日, D=4日
        let a = try store.addBook(title: "灰色の観測所", shelf: shelf, now: day(1))
        let b = try store.addBook(title: "遠い温室", shelf: shelf, now: day(3))
        let c = try store.addBook(title: "白い灯台の記録", shelf: shelf, now: day(2))
        let d = try store.addBook(title: "冬の回廊", shelf: shelf, now: day(4))
        // 購入日: A=10日, B=8日, C=12日, D=9日
        a.purchaseDate = day(10)
        b.purchaseDate = day(8)
        c.purchaseDate = day(12)
        d.purchaseDate = day(9)
        try store.context.save()
        return [a, b, c, d]
    }

    @Test("1冊の移動: 長押し＋横スワイプで1冊を別の位置へ動かすと、その位置に並び、他の本の順は保たれる")
    func moveOneBook() throws {
        let shelf = try genre("哲学・思想")
        let books = try seedFour(shelf)
        // 4冊目（冬の回廊）を2番目へ
        try store.moveBook(books[3], toIndex: 1)
        #expect(titles(shelf) == ["灰色の観測所", "冬の回廊", "遠い温室", "白い灯台の記録"])
        // 1冊目を末尾へ
        try store.moveBook(books[0], toIndex: 3)
        #expect(titles(shelf) == ["冬の回廊", "遠い温室", "白い灯台の記録", "灰色の観測所"])
        // 範囲外の指定は端に丸める
        try store.moveBook(books[0], toIndex: -5)
        #expect(titles(shelf) == ["灰色の観測所", "冬の回廊", "遠い温室", "白い灯台の記録"])
    }

    @Test("1冊の移動: 同じ棚の「買いたい」の本の並び順の値は変わらない")
    func moveKeepsWantedBooks() throws {
        let shelf = try genre("哲学・思想")
        let a = try store.addBook(title: "灰色の観測所", shelf: shelf)
        let wanted = try store.addBook(title: "静かな郵便局", shelf: shelf, ownership: .wanted)
        let b = try store.addBook(title: "遠い温室", shelf: shelf)
        let wantedOrder = wanted.sortOrder
        try store.moveBook(b, toIndex: 0)
        #expect(titles(shelf) == ["遠い温室", "灰色の観測所"])
        #expect(wanted.sortOrder == wantedOrder)
        #expect(a.sortOrder > b.sortOrder)
    }

    @Test("棚間移動: 移動先の末尾に並び、所持状況は変わらず、取り消すと元の棚の元の位置に戻る")
    func moveBetweenShelves() throws {
        let philosophy = try genre("哲学・思想")
        let history = try genre("歴史")
        let books = try seedFour(philosophy)
        try store.addBook(title: "古い地図について", shelf: history)

        let record = try store.moveBook(books[1], to: history)
        #expect(titles(philosophy) == ["灰色の観測所", "白い灯台の記録", "冬の回廊"])
        #expect(titles(history) == ["古い地図について", "遠い温室"])
        #expect(books[1].ownership == .owned)
        #expect(books[1].purchaseDate == day(8))

        try store.undoMove(record)
        #expect(titles(philosophy) == ["灰色の観測所", "遠い温室", "白い灯台の記録", "冬の回廊"])
        #expect(titles(history) == ["古い地図について"])
    }

    @Test("棚間移動: 0冊のジャンルへも移せる。買いたい本の棚へは移せない。買いたいの本は買いたいのまま")
    func moveToEmptyShelfAndWishlist() throws {
        let philosophy = try genre("哲学・思想")
        let religion = try genre("宗教")
        let book = try store.addBook(title: "眠る標本箱", shelf: philosophy)
        let wanted = try store.addBook(title: "長い時計の問題", shelf: philosophy, ownership: .wanted)
        try store.moveBook(book, to: religion)
        #expect(titles(religion) == ["眠る標本箱"])
        let wishlist = try #require(try store.wishlistShelf())
        #expect(throws: LibraryError.invalidShelfForBook) { try store.moveBook(book, to: wishlist) }
        try store.moveBook(wanted, to: religion)
        #expect(wanted.ownership == .wanted)
        #expect(wanted.shelf?.name == "宗教")
        #expect(titles(religion) == ["眠る標本箱"])
    }

    @Test("棚間移動の取り消し: その間に同じ位置の値の本が入っても、元の位置に戻る")
    func undoAfterAnotherBookWasAdded() throws {
        let philosophy = try genre("哲学・思想")
        let history = try genre("歴史")
        try store.addBook(title: "灰色の観測所", shelf: philosophy)
        let last = try store.addBook(title: "遠い温室", shelf: philosophy)
        let record = try store.moveBook(last, to: history)
        // 末尾の本が抜けたあとに追加された本は、同じ並び順の値になる
        try store.addBook(title: "小さな鯨", shelf: philosophy)
        try store.undoMove(record)
        #expect(titles(philosophy) == ["灰色の観測所", "遠い温室", "小さな鯨"])
    }

    @Test("購入日の新しい順・古い順")
    func sortByPurchaseDate() throws {
        let shelf = try genre("哲学・思想")
        _ = try seedFour(shelf)
        try store.sortBooks(in: shelf, by: .purchasedNewest)
        #expect(titles(shelf) == ["白い灯台の記録", "灰色の観測所", "冬の回廊", "遠い温室"])
        #expect(ShelfOrdering.isOrdered(store.books(in: shelf), by: .purchasedNewest))
        try store.sortBooks(in: shelf, by: .purchasedOldest)
        #expect(titles(shelf) == ["遠い温室", "冬の回廊", "灰色の観測所", "白い灯台の記録"])
    }

    @Test("購入日が同じ日なら、データ追加日で決まる")
    func samePurchaseDateFallsBackToAddedDate() throws {
        let shelf = try genre("哲学・思想")
        let books = try seedFour(shelf)
        for book in books { book.purchaseDate = day(20) }
        try store.context.save()
        try store.sortBooks(in: shelf, by: .purchasedNewest)
        #expect(titles(shelf) == ["冬の回廊", "遠い温室", "白い灯台の記録", "灰色の観測所"])
    }

    @Test("データ追加日の新しい順・古い順")
    func sortByAddedDate() throws {
        let shelf = try genre("哲学・思想")
        _ = try seedFour(shelf)
        try store.sortBooks(in: shelf, by: .addedNewest)
        #expect(titles(shelf) == ["冬の回廊", "遠い温室", "白い灯台の記録", "灰色の観測所"])
        try store.sortBooks(in: shelf, by: .addedOldest)
        #expect(titles(shelf) == ["灰色の観測所", "白い灯台の記録", "遠い温室", "冬の回廊"])
        // 整列後も手で並べ替えを続けられる
        try store.moveBook(try #require(store.books(in: shelf).last), toIndex: 0)
        #expect(titles(shelf) == ["冬の回廊", "灰色の観測所", "白い灯台の記録", "遠い温室"])
        #expect(!ShelfOrdering.isOrdered(store.books(in: shelf), by: .addedOldest))
    }

    @Test("題名順はよみで並ぶ（漢字の文字コードの順ではない）")
    func sortByTitleUsesYomi() throws {
        let shelf = try genre("哲学・思想")
        // よみ: とうだいのきろく・ねむるおんしつ・あおいくじら。文字コード順なら 灯 < 眠 < 青 になる
        try store.addBook(title: "灯台の記録", shelf: shelf)
        try store.addBook(title: "眠る温室", shelf: shelf)
        try store.addBook(title: "青い鯨", shelf: shelf)
        #expect(["灯台の記録", "眠る温室", "青い鯨"].sorted() == ["灯台の記録", "眠る温室", "青い鯨"])
        try store.sortBooks(in: shelf, by: .title)
        #expect(titles(shelf) == ["青い鯨", "灯台の記録", "眠る温室"])
    }

    @Test("題名順: ひらがな・カタカナ、英字の大文字・小文字を区別しない")
    func sortByTitleIgnoresKanaAndCase() throws {
        let shelf = try genre("哲学・思想")
        try store.addBook(title: "ミモザの午後", shelf: shelf)
        try store.addBook(title: "あさがおの図鑑", shelf: shelf)
        try store.addBook(title: "beta Notes", shelf: shelf)
        try store.addBook(title: "Alpha Notes", shelf: shelf)
        try store.sortBooks(in: shelf, by: .title)
        #expect(titles(shelf) == ["Alpha Notes", "beta Notes", "あさがおの図鑑", "ミモザの午後"])
    }

    @Test("手動に戻す: 整列の前の並びに戻せる。手動を選んでも並びは変わらない")
    func restoreManualOrder() throws {
        let shelf = try genre("哲学・思想")
        let books = try seedFour(shelf)
        try store.moveBook(books[3], toIndex: 0)
        let manual = store.books(in: shelf).map(\.id)
        try store.sortBooks(in: shelf, by: .title)
        try store.sortBooks(in: shelf, by: .manual)
        #expect(store.books(in: shelf).map(\.id) != manual)
        try store.restoreOrder(in: shelf, ids: manual)
        #expect(store.books(in: shelf).map(\.id) == manual)
    }

    @Test("並べ替えは保存され、再起動相当の新しいコンテナでも保たれる")
    func orderPersists() throws {
        let shelf = try genre("哲学・思想")
        let books = try seedFour(shelf)
        try store.moveBook(books[2], toIndex: 0)
        let config = ModelConfiguration(url: folder.appendingPathComponent("library.store"))
        let container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        let reopened = LibraryStore(container: container, images: images)
        let shelf2 = try #require(try reopened.shelves().first(where: { $0.name == "哲学・思想" }))
        #expect(reopened.books(in: shelf2).map(\.title) == ["白い灯台の記録", "灰色の観測所", "遠い温室", "冬の回廊"])
    }
}
