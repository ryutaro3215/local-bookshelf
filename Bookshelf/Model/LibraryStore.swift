import Foundation
import SwiftData

enum LibraryError: Error, Equatable {
    /// 買いたい本・未分類は削除・名前変更できない
    case systemShelfIsProtected
    /// 本の所属先にできない棚（買いたい本）を指定した
    case invalidShelfForBook
    /// 題名・ジャンル名が空（制御文字を除いた結果を含む）
    case emptyName
    /// 未分類の棚が見つからない（初期化前）
    case missingUnsortedShelf
}

/// 本とジャンルの操作をまとめる（requirements §10・F4）。
@MainActor
final class LibraryStore {
    /// 題名・ジャンル名の上限（requirements S6）
    static let maxNameLength = 200

    /// コンテナを保持し、使っている間に解放されないようにする
    let container: ModelContainer
    let context: ModelContext
    let images: ImageStore
    private let calendar: Calendar

    init(container: ModelContainer, images: ImageStore, calendar: Calendar = .current) {
        self.container = container
        self.context = container.mainContext
        self.images = images
        self.calendar = calendar
    }

    // MARK: - 入力の整え方（S6）

    /// 制御文字を除き、前後の空白を落として、200文字までに切り詰める
    static func sanitize(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxNameLength))
    }

    // MARK: - 初期化

    /// 棚が1つもなければ、初期ジャンル28個とシステム棚（買いたい本・未分類）を作る
    func seedIfNeeded() throws {
        let count = try context.fetchCount(FetchDescriptor<Shelf>())
        guard count == 0 else { return }
        var order = 0
        for genre in InitialGenres.genres {
            context.insert(
                Shelf(name: genre.name, nameEn: genre.nameEn, categoryID: genre.category.id, sortOrder: order))
            order += 1
        }
        context.insert(
            Shelf(
                name: InitialGenres.wishlist.name, nameEn: InitialGenres.wishlist.nameEn,
                categoryID: InitialGenres.system.id, sortOrder: order, kind: .wishlist))
        order += 1
        context.insert(
            Shelf(
                name: InitialGenres.unsorted.name, nameEn: InitialGenres.unsorted.nameEn,
                categoryID: InitialGenres.system.id, sortOrder: order, kind: .unsorted))
        try context.save()
    }

    // MARK: - 棚の取得

    /// 全ての棚（並び順）
    func shelves() throws -> [Shelf] {
        try context.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    func unsortedShelf() throws -> Shelf {
        guard let shelf = try shelves().first(where: { $0.kind == .unsorted }) else {
            throw LibraryError.missingUnsortedShelf
        }
        return shelf
    }

    func wishlistShelf() throws -> Shelf? {
        try shelves().first(where: { $0.kind == .wishlist })
    }

    // MARK: - 本の一覧

    /// ジャンル別の一覧（購入済みの本だけ。並び順）
    func books(in shelf: Shelf) -> [Book] {
        shelf.books.filter { $0.ownership == .owned }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 買いたい本の一覧（所持状況が「買いたい」の本。データ追加日の順）
    func wishlistBooks() throws -> [Book] {
        let wanted = Ownership.wanted.rawValue
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.ownershipRaw == wanted }, sortBy: [SortDescriptor(\.addedAt)])
        return try context.fetch(descriptor)
    }

    // MARK: - 本の追加・削除

    /// 本を追加する。ジャンルの末尾に並ぶ。購入済みなら購入日はデータ追加日の日付
    @discardableResult
    func addBook(
        title: String, shelf: Shelf?, ownership: Ownership = .owned, now: Date = .now, id: UUID = UUID()
    ) throws -> Book {
        let cleanTitle = Self.sanitize(title)
        guard !cleanTitle.isEmpty else { throw LibraryError.emptyName }
        let target = try shelf ?? unsortedShelf()
        guard target.kind != .wishlist else { throw LibraryError.invalidShelfForBook }

        let book = Book(
            id: id,
            title: cleanTitle,
            yomi: Yomi.make(from: cleanTitle),
            addedAt: now,
            ownership: ownership,
            purchaseDate: ownership == .owned ? calendar.startOfDay(for: now) : nil,
            sortOrder: nextSortOrder(in: target),
            shelf: target)
        context.insert(book)
        try context.save()
        return book
    }

    /// 本と表紙画像（原寸・サムネイル）を消す。データの削除が保存できてから画像を消す
    /// （保存に失敗したときに、本だけ残って画像が消えた状態にしないため）
    func deleteBook(_ book: Book) throws {
        let id = book.id
        context.delete(book)
        try context.save()
        try images.delete(for: id)
    }

    // MARK: - 所持状況（§10.3）

    /// 「買いたい」にすると購入日を消す。「購入済み」にすると購入日を今日にする。ジャンルは変えない
    func setOwnership(_ book: Book, to ownership: Ownership, now: Date = .now) throws {
        guard book.ownership != ownership else { return }
        book.ownership = ownership
        book.purchaseDate = ownership == .owned ? calendar.startOfDay(for: now) : nil
        try context.save()
    }

    // MARK: - ジャンルの管理（F4）

    /// ジャンルを追加する（既定は区分「マイジャンル」）。システム棚の前に入れる
    @discardableResult
    func addGenre(name: String, categoryID: String = InitialGenres.myGenres.id) throws -> Shelf {
        let cleanName = Self.sanitize(name)
        guard !cleanName.isEmpty else { throw LibraryError.emptyName }
        let all = try shelves()
        let firstSystemOrder = all.first(where: { $0.isSystem })?.sortOrder ?? (all.last?.sortOrder ?? -1) + 1
        for shelf in all where shelf.sortOrder >= firstSystemOrder {
            shelf.sortOrder += 1
        }
        let shelf = Shelf(name: cleanName, categoryID: categoryID, sortOrder: firstSystemOrder)
        context.insert(shelf)
        try context.save()
        return shelf
    }

    func renameShelf(_ shelf: Shelf, to name: String) throws {
        guard !shelf.isSystem else { throw LibraryError.systemShelfIsProtected }
        let cleanName = Self.sanitize(name)
        guard !cleanName.isEmpty else { throw LibraryError.emptyName }
        shelf.name = cleanName
        shelf.nameEn = nil
        try context.save()
    }

    /// ジャンルを消す。中の本は未分類の末尾へ移す（所持状況は変えない）
    func deleteShelf(_ shelf: Shelf) throws {
        guard !shelf.isSystem else { throw LibraryError.systemShelfIsProtected }
        let unsorted = try unsortedShelf()
        var order = nextSortOrder(in: unsorted)
        for book in shelf.books.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            book.shelf = unsorted
            book.sortOrder = order
            order += 1
        }
        context.delete(shelf)
        try context.save()
    }

    // MARK: - 内部

    private func nextSortOrder(in shelf: Shelf) -> Int {
        (shelf.books.map(\.sortOrder).max() ?? -1) + 1
    }
}
