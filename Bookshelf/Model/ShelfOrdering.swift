import Foundation
import SwiftData

/// 棚の並べ順（F5-3。「表示」メニューの「この棚の並べ順」）
nonisolated enum ShelfSortKey: String, CaseIterable, Sendable {
    /// 手動（自分で並べた順）
    case manual
    /// 購入日が新しい順
    case purchasedNewest
    /// 購入日が古い順
    case purchasedOldest
    /// データ追加日が新しい順
    case addedNewest
    /// データ追加日が古い順
    case addedOldest
    /// 題名順（内部項目「よみ」の順。F7-1）
    case title

    /// メニューに出す名前
    var label: String {
        switch self {
        case .manual: "手動（自分で並べた順）"
        case .purchasedNewest: "購入日が新しい順"
        case .purchasedOldest: "購入日が古い順"
        case .addedNewest: "データ追加日が新しい順"
        case .addedOldest: "データ追加日が古い順"
        case .title: "題名順"
        }
    }
}

/// 棚の中の並び順を決める（並べ替え・一括整列。F5-1・F5-3）。
/// 並び順は `Book.sortOrder` の値の入れ替えで表す（同じ棚の「買いたい」の本の値は動かさない）
enum ShelfOrdering {
    /// `list` の `from` 番目を `to` 番目へ動かした並び（範囲外は端に丸める）
    static func moved<T>(_ list: [T], from: Int, to: Int) -> [T] {
        guard list.indices.contains(from) else { return list }
        var result = list
        let element = result.remove(at: from)
        result.insert(element, at: min(max(to, 0), result.count))
        return result
    }

    /// `key` の順に並べた本。手動はそのまま返す。同じ値のときはデータ追加日（同じ向き）→題名で決める
    static func sorted(_ books: [Book], by key: ShelfSortKey) -> [Book] {
        switch key {
        case .manual:
            return books
        case .purchasedNewest, .purchasedOldest:
            let newest = key == .purchasedNewest
            return books.sorted { a, b in
                switch (a.purchaseDate, b.purchaseDate) {
                case (let x?, let y?) where x != y: return newest ? x > y : x < y
                case (nil, .some): return false
                case (.some, nil): return true
                default: return added(a, b, newest: newest)
                }
            }
        case .addedNewest, .addedOldest:
            let newest = key == .addedNewest
            return books.sorted { added($0, $1, newest: newest) }
        case .title:
            return books.sorted { a, b in
                let order = compareYomi(a.yomi, b.yomi)
                if order != .orderedSame { return order == .orderedAscending }
                let titleOrder = a.title.compare(b.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return a.addedAt < b.addedAt
            }
        }
    }

    /// 本がすでに `key` の順に並んでいるか（手動は常に true）
    static func isOrdered(_ books: [Book], by key: ShelfSortKey) -> Bool {
        sorted(books, by: key).map(\.id) == books.map(\.id)
    }

    /// よみの比較。ひらがな・カタカナ、英字の大文字・小文字、全角・半角を区別せず、数字は数の大きさで比べる
    static func compareYomi(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(
            b, options: [.caseInsensitive, .widthInsensitive, .numeric],
            range: nil, locale: Locale(identifier: "ja_JP"))
    }

    private static func added(_ a: Book, _ b: Book, newest: Bool) -> Bool {
        if a.addedAt != b.addedAt {
            return newest ? a.addedAt > b.addedAt : a.addedAt < b.addedAt
        }
        return a.title < b.title
    }
}

/// 棚間移動を取り消すための記録（D-3 の「取り消す」で元の棚・元の位置へ戻す）
struct ShelfMoveRecord {
    let book: Book
    /// 本の ID（移したときに控える。本が削除されたあとでも、本のデータを読まずに比べられる）
    let bookID: UUID
    let fromShelf: Shelf
    let fromSortOrder: Int
    let toShelf: Shelf
}

extension LibraryStore {
    /// `books`（同じ棚の本）を、この並びのとおりに並べ直して保存する。
    /// 今の `sortOrder` の値を小さい順に振り直すので、ほかの本（同じ棚の「買いたい」の本）の位置は変わらない
    func applyOrder(_ books: [Book]) throws {
        let values = books.map(\.sortOrder).sorted()
        for (book, value) in zip(books, values) where book.sortOrder != value {
            book.sortOrder = value
        }
        try commit()
    }

    /// 1冊を、その棚の一覧（購入済みの本）の `index` 番目へ動かす（長押し＋横スワイプ。F5-1）
    func moveBook(_ book: Book, toIndex index: Int) throws {
        guard let shelf = book.shelf else { return }
        let list = books(in: shelf)
        guard let from = list.firstIndex(where: { $0.id == book.id }) else { return }
        try applyOrder(ShelfOrdering.moved(list, from: from, to: index))
    }

    /// 棚の本（購入済みの本）を一括で整列する（F5-3）。手動は何もしない
    func sortBooks(in shelf: Shelf, by key: ShelfSortKey) throws {
        guard key != .manual else { return }
        try applyOrder(ShelfOrdering.sorted(books(in: shelf), by: key))
    }

    /// 棚の本を `ids` の並びに戻す（整列の前の手動の並びに戻すとき）。`ids` に無い本は今の順のまま後ろに置く
    func restoreOrder(in shelf: Shelf, ids: [UUID]) throws {
        let list = books(in: shelf)
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = list.filter { rank[$0.id] != nil }.sorted { rank[$0.id, default: 0] < rank[$1.id, default: 0] }
        let rest = list.filter { rank[$0.id] == nil }
        try applyOrder(known + rest)
    }

    /// 本を別の棚の末尾へ移す（長押し＋上スワイプ・グリッドのメニュー。F5-2）。所持状況は変えない。
    /// 戻り値で `undoMove` を呼ぶと元の棚・元の位置へ戻る
    @discardableResult
    func moveBook(_ book: Book, to shelf: Shelf) throws -> ShelfMoveRecord {
        guard shelf.kind != .wishlist else { throw LibraryError.invalidShelfForBook }
        let from = try book.shelf ?? unsortedShelf()
        let record = ShelfMoveRecord(
            book: book, bookID: book.id, fromShelf: from, fromSortOrder: book.sortOrder, toShelf: shelf)
        guard from.persistentModelID != shelf.persistentModelID else { return record }
        let next = (shelf.books.map(\.sortOrder).max() ?? -1) + 1
        book.shelf = shelf
        book.sortOrder = next
        try commit()
        return record
    }

    /// 棚間移動を取り消す。元の棚の、元の位置（並び順の値）へ戻す。
    /// その間に同じ値の本が入っていたら、その本から後ろを1つずつずらして元の位置を空ける
    /// 本・元の棚が削除されていたら何も変えずに投げる（N-060。移した本をトーストが出ている間に削除したとき）
    func undoMove(_ record: ShelfMoveRecord) throws {
        let book = record.book
        let shelf = record.fromShelf
        guard try containsBook(id: record.bookID), !book.isDeleted, book.modelContext != nil else {
            throw LibraryError.bookNotFound
        }
        guard try shelves().contains(where: { $0.persistentModelID == shelf.persistentModelID }) else {
            throw LibraryError.shelfNotFound
        }
        let others = shelf.books.filter { $0.id != book.id }
        if others.contains(where: { $0.sortOrder == record.fromSortOrder }) {
            for other in others where other.sortOrder >= record.fromSortOrder {
                other.sortOrder += 1
            }
        }
        book.shelf = shelf
        book.sortOrder = record.fromSortOrder
        try commit()
    }

    /// この ID の本がまだ保存されているか（削除済みなら false）
    func containsBook(id: UUID) throws -> Bool {
        return try context.fetchCount(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })) > 0
    }
}
