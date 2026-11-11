import Foundation
import SwiftData
import Testing

@testable import Bookshelf

/// ジャンルの管理（plan T8。F4）のデータの整合と、移動の取り消しの安全（N-060）
@MainActor
struct GenreManagementTests {
    let store: LibraryStore

    init() throws {
        let schema = Schema([Book.self, Shelf.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let images = ImageStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "GenreManagementTests-\(UUID().uuidString)", isDirectory: true))
        store = LibraryStore(container: container, images: images)
        try store.seedIfNeeded()
    }

    func genre(_ name: String) throws -> Shelf {
        try #require(try store.shelves().first(where: { $0.name == name }))
    }

    /// 並び順が 0 から欠番・重複なしで並んでいる
    func expectDenseOrder() throws {
        #expect(try store.shelves().map(\.sortOrder) == Array(0..<(try store.shelves().count)))
    }

    @Test("選んだ区分の末尾に追加される（マイジャンルはシステム棚の前）")
    func addGenrePlacesAtEndOfCategory() throws {
        let added = try store.addGenre(name: "灯台守の書架", categoryID: InitialGenres.humanities.id)
        let names = try store.shelves().map(\.name)
        let index = try #require(names.firstIndex(of: "灯台守の書架"))
        #expect(names[index - 1] == "言語・語学")
        #expect(names[index + 1] == "政治・法律")
        #expect(added.categoryID == InitialGenres.humanities.id)

        try store.addGenre(name: "夜更けの書架")
        #expect(Array(try store.shelves().map(\.name).suffix(3)) == ["夜更けの書架", "買いたい本", "未分類"])
        try expectDenseOrder()
    }

    @Test("ジャンルの無い区分に追加すると、区分の順で前の区分の後ろに入る")
    func addGenreToEmptyCategory() throws {
        for shelf in try store.shelves() where shelf.categoryID == InitialGenres.technology.id {
            try store.deleteShelf(shelf)
        }
        try store.addGenre(name: "古い観測所", categoryID: InitialGenres.technology.id)
        let names = try store.shelves().map(\.name)
        let index = try #require(names.firstIndex(of: "古い観測所"))
        #expect(names[index - 1] == "地球・宇宙")
        #expect(names[index + 1] == "芸術・デザイン")
        try expectDenseOrder()
    }

    @Test("システムの区分や知らない区分には追加できない・名前は S6 で整える")
    func addGenreValidates() throws {
        #expect(throws: LibraryError.invalidCategory) {
            try store.addGenre(name: "白い温室", categoryID: InitialGenres.system.id)
        }
        #expect(throws: LibraryError.invalidCategory) { try store.addGenre(name: "白い温室", categoryID: "unknown") }
        #expect(throws: LibraryError.emptyName) { try store.addGenre(name: " \u{0007}\n") }
        let shelf = try store.addGenre(name: " 白い\u{0007}温室 ")
        #expect(shelf.name == "白い温室")
    }

    @Test("並び替えは同じ区分の中だけで、ほかの区分の並びは変わらない")
    func moveGenreWithinCategory() throws {
        let before = try store.shelves().map(\.name)
        try store.moveGenre(try genre("言語・語学"), toIndex: 0)
        let after = try store.shelves().map(\.name)
        #expect(Array(after[5..<10]) == ["言語・語学", "哲学・思想", "宗教", "歴史", "心理"])
        #expect(Array(after[0..<5]) == Array(before[0..<5]))
        #expect(Array(after[10...]) == Array(before[10...]))
        try expectDenseOrder()

        try store.moveGenre(try genre("言語・語学"), toIndex: 99)
        #expect(try store.shelves().map(\.name) == before)
        #expect(throws: LibraryError.systemShelfIsProtected) { try store.moveGenre(try genre("未分類"), toIndex: 0) }
    }

    @Test("削除したジャンルの本（購入済み・買いたい）は未分類の末尾へ移り、並び順に欠番が残らない")
    func deleteGenreMovesBooksAndKeepsOrderDense() throws {
        let unsorted = try store.unsortedShelf()
        let history = try genre("歴史")
        try store.addBook(title: "眠る地図", shelf: unsorted)
        try store.addBook(title: "遠い灯台", shelf: history)
        try store.addBook(title: "冬の回廊", shelf: history, ownership: .wanted)
        try store.addBook(title: "青い時計", shelf: history)

        try store.deleteShelf(history)

        #expect(try store.shelves().contains { $0.name == "歴史" } == false)
        #expect(store.books(in: unsorted).map(\.title) == ["眠る地図", "遠い灯台", "青い時計"])
        #expect(unsorted.books.sorted { $0.sortOrder < $1.sortOrder }.map(\.title) == ["眠る地図", "遠い灯台", "冬の回廊", "青い時計"])
        #expect(try store.wishlistBooks().first?.shelf?.kind == .unsorted)
        try expectDenseOrder()
    }

    @Test("移した本を削除したあとの取り消しは失敗し、元の棚の並び順を変えない（N-060）")
    func undoAfterDeleteFailsSafely() throws {
        let philosophy = try genre("哲学・思想")
        let first = try store.addBook(title: "灰色の標本箱", shelf: philosophy)
        let second = try store.addBook(title: "静かな郵便局", shelf: philosophy)
        let third = try store.addBook(title: "小さな植物園", shelf: philosophy)
        let record = try store.moveBook(first, to: try genre("宗教"))
        try store.deleteBook(first)

        #expect(throws: LibraryError.bookNotFound) { try store.undoMove(record) }
        #expect(second.sortOrder == 1)
        #expect(third.sortOrder == 2)
        #expect(store.books(in: philosophy).map(\.title) == ["静かな郵便局", "小さな植物園"])
    }

    @Test("元の棚が削除されていたら取り消しは失敗する")
    func undoAfterShelfDeletedFailsSafely() throws {
        let essays = try genre("エッセイ")
        let book = try store.addBook(title: "長い鯨の手帖", shelf: essays)
        let record = try store.moveBook(book, to: try genre("詩歌"))
        try store.deleteShelf(essays)

        #expect(throws: LibraryError.shelfNotFound) { try store.undoMove(record) }
        #expect(book.shelf?.name == "詩歌")
    }
}
