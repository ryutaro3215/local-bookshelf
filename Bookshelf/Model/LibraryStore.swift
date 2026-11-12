import Foundation
import SwiftData
import os

enum LibraryError: Error, Equatable {
    /// 買いたい本・未分類は削除・名前変更できない
    case systemShelfIsProtected
    /// 本の所属先にできない棚（買いたい本）を指定した
    case invalidShelfForBook
    /// 題名・ジャンル名が空（制御文字を除いた結果を含む）
    case emptyName
    /// 未分類の棚が見つからない（初期化前）
    case missingUnsortedShelf
    /// 本がすでに削除されている（取り消しの対象が無い。N-060）
    case bookNotFound
    /// 棚がすでに削除されている（取り消しの戻り先が無い）
    case shelfNotFound
    /// 区分が無い・ジャンルを置けない区分（システム）を指定した
    case invalidCategory
    /// 本のデータは保存できたが、新しい表紙の画像に入れ替えられなかった（古い表紙のまま）
    case coverNotReplaced
}

/// 編集画面（E-6・E-7）で確定した値（F6-4・§10.3）
struct BookEdit {
    var title: String
    /// ジャンル（買いたい本の棚は選べない）
    var shelf: Shelf
    var ownership: Ownership
    /// 購入日（購入済みのときだけ使う。日付だけを保存する）
    var purchaseDate: Date?
}

/// 本とジャンルの操作をまとめる（requirements §10・F4）。
@MainActor
final class LibraryStore {
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "LibraryStore")
    /// 題名・ジャンル名の上限（requirements S6）
    static let maxNameLength = 200

    /// コンテナを保持し、使っている間に解放されないようにする
    let container: ModelContainer
    let context: ModelContext
    let images: ImageStore
    let calendar: Calendar

    init(container: ModelContainer, images: ImageStore, calendar: Calendar = .current) {
        self.container = container
        self.context = container.mainContext
        self.images = images
        self.calendar = calendar
    }

    // MARK: - 保存（N-061）

    /// 変更を保存する。保存に失敗したら、メモリ上の変更を取り消してから投げる
    /// （失敗を伝えた変更が、次の別の保存で一緒に保存されないようにする）
    func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
        try commit()
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

    // MARK: - 検索（F7。T10）

    /// 購入済みの本を、全ジャンルから題名とよみの部分一致で探す（F7-1・F7-4。「買いたい」の本は含めない）。
    /// 空の検索語は結果なし。並びは購入日の新しい順（同じ日はデータ追加日の新しい順）
    func searchOwnedBooks(matching query: String) throws -> [Book] {
        let owned = Ownership.owned.rawValue
        let books = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.ownershipRaw == owned }))
        return Self.search(books, matching: query)
    }

    /// 本の一覧から検索する（画面は @Query の一覧をそのまま渡す。「買いたい」の本はここでも除く）
    static func search(_ books: [Book], matching query: String) -> [Book] {
        let key = SearchText.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return [] }
        return books.filter { book in
            book.ownership == .owned
                && (SearchText.normalize(book.title).contains(key) || SearchText.normalize(book.yomi).contains(key))
        }
        .sorted { lhs, rhs in
            let left = lhs.purchaseDate ?? .distantPast
            let right = rhs.purchaseDate ?? .distantPast
            return left != right ? left > right : lhs.addedAt > rhs.addedAt
        }
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
        try commit()
        return book
    }

    /// 本と表紙画像（原寸・サムネイル）を消す。データの削除が保存できてから画像を消す
    /// （保存に失敗したときに、本だけ残って画像が消えた状態にしないため）
    func deleteBook(_ book: Book) throws {
        let id = book.id
        context.delete(book)
        try commit()
        try images.delete(for: id)
    }

    // MARK: - 所持状況（§10.3）

    /// 「買いたい」にすると購入日を消す。「購入済み」にすると購入日を今日にする。ジャンルは変えない
    func setOwnership(_ book: Book, to ownership: Ownership, now: Date = .now) throws {
        guard book.ownership != ownership else { return }
        book.ownership = ownership
        book.purchaseDate = ownership == .owned ? calendar.startOfDay(for: now) : nil
        try commit()
    }

    // MARK: - 本の編集（F6-4・§10.3。T9）

    /// 編集画面の「完了」。題名・ジャンル・所持状況・購入日を変え、新しい表紙があれば入れ替える。
    /// - ジャンルを変えた本、「買いたい」から「購入済み」にした本は、そのジャンルの末尾に並ぶ（「購入した」と同じ）
    /// - 「買いたい」にすると購入日を消す（ジャンルは残す）
    /// - 表紙は、まず仮の名前で書き出し、データの保存が成功してから入れ替える。保存に失敗したら仮のファイルを消し、
    ///   古い表紙をそのまま残す（失敗したときは commit() がメモリ上の変更も取り消す）
    func updateBook(_ book: Book, with edit: BookEdit, newCover: ProcessedCover? = nil) throws {
        let cleanTitle = Self.sanitize(edit.title)
        guard !cleanTitle.isEmpty else { throw LibraryError.emptyName }
        guard edit.shelf.kind != .wishlist else { throw LibraryError.invalidShelfForBook }
        guard try containsBook(id: book.id), !book.isDeleted else { throw LibraryError.bookNotFound }

        // 新しい表紙は仮の ID で先に書き出す（ここで失敗しても、データも古い表紙も変わらない）
        let stagingID = UUID()
        if let newCover {
            do {
                try images.save(original: newCover.image, thumbnail: newCover.thumbnail, for: stagingID)
            } catch {
                discardStaged(stagingID)
                throw error
            }
        }

        let wasOwned = book.ownership == .owned
        let shelfChanged = book.shelf?.persistentModelID != edit.shelf.persistentModelID
        if book.title != cleanTitle {
            book.title = cleanTitle
            book.yomi = Yomi.make(from: cleanTitle)
        }
        if shelfChanged || (!wasOwned && edit.ownership == .owned) {
            book.sortOrder = nextSortOrder(in: edit.shelf, excluding: book)
        }
        if shelfChanged {
            book.shelf = edit.shelf
        }
        book.ownership = edit.ownership
        book.purchaseDate = edit.ownership == .owned ? calendar.startOfDay(for: edit.purchaseDate ?? .now) : nil
        do {
            try commit()
        } catch {
            if newCover != nil { discardStaged(stagingID) }
            throw error
        }

        guard newCover != nil else { return }
        do {
            try replaceFile(images.originalURL(for: book.id), with: images.originalURL(for: stagingID))
            try replaceFile(images.thumbnailURL(for: book.id), with: images.thumbnailURL(for: stagingID))
        } catch {
            discardStaged(stagingID)
            throw LibraryError.coverNotReplaced
        }
    }

    /// 仮に書き出した表紙を消す（消せなくても本のデータには関係しないので、記録だけ残す）
    private func discardStaged(_ id: UUID) {
        do {
            try images.delete(for: id)
        } catch {
            Self.logger.error("仮の表紙を消せない: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `target` を `staged` の中身に入れ替える（target が無ければ移すだけ）
    private func replaceFile(_ target: URL, with staged: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: target)
        }
    }

    // MARK: - ジャンルの管理（F4）

    /// ジャンルを追加する（既定は区分「マイジャンル」）。選んだ区分の末尾に置く（F-3「選んだ区分の末尾に追加」）。
    /// その区分にまだジャンルが無いときは、区分の順（InitialGenres.categories）で前にある区分の後ろに置く
    @discardableResult
    func addGenre(name: String, categoryID: String = InitialGenres.myGenres.id) throws -> Shelf {
        let cleanName = Self.sanitize(name)
        guard !cleanName.isEmpty else { throw LibraryError.emptyName }
        guard let rank = Self.categoryRank(categoryID), categoryID != InitialGenres.system.id else {
            throw LibraryError.invalidCategory
        }
        let all = try shelves()
        // 自分の区分まで（区分の順で前のもの）の最後の棚の、すぐ後ろ。システム棚より前
        let index =
            all.lastIndex(where: { !$0.isSystem && (Self.categoryRank($0.categoryID) ?? Int.max) <= rank })
            .map { $0 + 1 } ?? 0
        var ordered = all
        let shelf = Shelf(name: cleanName, categoryID: categoryID, sortOrder: 0)
        context.insert(shelf)
        ordered.insert(shelf, at: index)
        renumber(ordered)
        try commit()
        return shelf
    }

    /// ジャンルの並びを変える（F4-2）。同じ区分のジャンルの中で `index` 番目へ動かす（範囲外は端に丸める）。
    /// 区分の中の今の並び順の値を入れ替えるので、ほかの区分の並びは変わらない
    func moveGenre(_ shelf: Shelf, toIndex index: Int) throws {
        guard !shelf.isSystem else { throw LibraryError.systemShelfIsProtected }
        let siblings = try shelves().filter { !$0.isSystem && $0.categoryID == shelf.categoryID }
        guard let from = siblings.firstIndex(where: { $0.persistentModelID == shelf.persistentModelID }) else {
            return
        }
        let moved = ShelfOrdering.moved(siblings, from: from, to: index)
        let values = siblings.map(\.sortOrder).sorted()
        for (item, value) in zip(moved, values) where item.sortOrder != value {
            item.sortOrder = value
        }
        try commit()
    }

    func renameShelf(_ shelf: Shelf, to name: String) throws {
        guard !shelf.isSystem else { throw LibraryError.systemShelfIsProtected }
        let cleanName = Self.sanitize(name)
        guard !cleanName.isEmpty else { throw LibraryError.emptyName }
        shelf.name = cleanName
        shelf.nameEn = nil
        try commit()
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
        let remaining = try shelves().filter { $0.persistentModelID != shelf.persistentModelID }
        context.delete(shelf)
        // 棚どうしの並び順を詰める（欠番を残さない）
        renumber(remaining)
        try commit()
    }

    // MARK: - 内部

    /// 区分の順番（InitialGenres.categories の位置）。知らない区分は nil
    static func categoryRank(_ id: String) -> Int? {
        InitialGenres.categories.firstIndex { $0.id == id }
    }

    /// 棚の並び順をこの並びのとおり 0 から振り直す
    private func renumber(_ ordered: [Shelf]) {
        for (value, shelf) in ordered.enumerated() where shelf.sortOrder != value {
            shelf.sortOrder = value
        }
    }

    func nextSortOrder(in shelf: Shelf, excluding book: Book? = nil) -> Int {
        let others = shelf.books.filter { $0.persistentModelID != book?.persistentModelID }
        return (others.map(\.sortOrder).max() ?? -1) + 1
    }
}

/// 検索の文字の比べ方（F7-1）。
/// NFKC（全角英数→半角、半角カナ→全角など）→ 小文字 → カタカナをひらがなに、の順にそろえてから部分一致で比べる。
/// 濁点・半濁点は区別する（「はし」で「ばし」は出さない）
nonisolated enum SearchText {
    static func normalize(_ text: String) -> String {
        hiragana(text.precomposedStringWithCompatibilityMapping.lowercased())
    }

    /// カタカナ（ァ〜ヶ）をひらがな（ぁ〜ゖ）にずらす。長音「ー」などはそのまま
    static func hiragana(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value), let shifted = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(shifted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// `text` の中で `query` に一致する部分（元の文字列の範囲。強調表示用）。よみだけで一致したときは空
    static func matchRanges(of query: String, in text: String) -> [Range<String.Index>] {
        let key = Array(normalize(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard !key.isEmpty else { return [] }
        // 1文字ずつそろえ、そろえた後の文字がどの元の文字から来たかを覚えておく
        var folded: [Character] = []
        var sources: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            for character in normalize(String(text[index..<next])) {
                folded.append(character)
                sources.append(index..<next)
            }
            index = next
        }
        var ranges: [Range<String.Index>] = []
        var position = 0
        while position + key.count <= folded.count {
            if Array(folded[position..<(position + key.count)]) == key {
                let range = sources[position].lowerBound..<sources[position + key.count - 1].upperBound
                if let last = ranges.last, last.upperBound >= range.lowerBound {
                    ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
                } else {
                    ranges.append(range)
                }
                position += key.count
            } else {
                position += 1
            }
        }
        return ranges
    }
}
