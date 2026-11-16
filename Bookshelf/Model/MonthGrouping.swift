import Foundation

/// 購入月別のまとめる単位（F6-7）。ピンチインで年、ピンチアウトで月
enum PurchasePeriod: Equatable, Sendable {
    case month
    case year
}

/// 購入月別の1まとまり（その月・その年に購入した本）
struct PurchaseGroup: Identifiable {
    let period: PurchasePeriod
    let year: Int
    /// 月（1〜12）。年のまとまりでは nil
    let month: Int?
    /// 購入日の古い順（1日 → 31日）
    let books: [Book]

    var id: String { month.map { "\(year)-\($0)" } ?? "\(year)" }
    /// 上部・見出しに出す名前（「2026年10月」「2026年」）
    var title: String { month.map { "\(year)年\($0)月" } ?? "\(year)年" }
    /// 画面に出す名前。日本語表示では `title`、英語表示では端末のロケールの書式（「October 2026」「2026」。T15）
    var displayTitle: String {
        guard InitialGenres.displaysInEnglish else { return title }
        guard let month, let date = Self.firstDay(year: year, month: month) else { return String(year) }
        return date.formatted(.dateTime.year().month(.wide))
    }

    /// 年の表示の月の並び（J-2「8月」。英語表示では「Aug」など端末のロケールの短い月名。T15）
    static func monthLabel(_ month: Int) -> String {
        guard InitialGenres.displaysInEnglish, let date = firstDay(year: 2001, month: month) else { return "\(month)月" }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private static func firstDay(year: Int, month: Int) -> Date? {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 15))
    }
}

/// 購入月別で、どのまとまりのどの本を見ているか。月と年を切り替えても同じ本を見せる
struct MonthFocus: Equatable {
    var groupID: String?
    var bookID: UUID?
    var index = 0
}

/// 購入月別のまとめ方（F6-7・§10.3）
enum MonthGrouping {
    /// 購入済みで購入日のある本を月か年でまとめる（「買いたい」の本と、本のない月・年は含めない）。
    /// まとまりは新しい順（いちばん上が最新）、中の並びは購入日の古い順。同じ日はデータ追加日の古い順
    static func groups(of books: [Book], by period: PurchasePeriod, calendar: Calendar = .current)
        -> [PurchaseGroup]
    {
        struct Key: Hashable {
            let year: Int
            let month: Int?
        }
        var buckets: [Key: [Book]] = [:]
        for book in books where book.ownership == .owned {
            guard let date = book.purchaseDate else { continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { continue }
            buckets[Key(year: year, month: period == .month ? month : nil), default: []].append(book)
        }
        return
            buckets
            .sorted { lhs, rhs in
                lhs.key.year != rhs.key.year ? lhs.key.year > rhs.key.year : (lhs.key.month ?? 0) > (rhs.key.month ?? 0)
            }
            .map { key, list in
                PurchaseGroup(period: period, year: key.year, month: key.month, books: list.sorted(by: isEarlier))
            }
    }

    /// 年のまとまりに入っている月（古い順）。年の表示で、今の本の月を示す並び（J-2）に使う
    static func months(in group: PurchaseGroup, calendar: Calendar = .current) -> [Int] {
        if let month = group.month { return [month] }
        let months = group.books.compactMap { $0.purchaseDate.map { calendar.component(.month, from: $0) } }
        return Array(Set(months)).sorted()
    }

    /// 本の購入月
    static func month(of book: Book, calendar: Calendar = .current) -> Int? {
        book.purchaseDate.map { calendar.component(.month, from: $0) }
    }

    /// 見ている本を含むまとまり（無ければ同じ名前のまとまり、それも無ければ最新のまとまり）と、その中の位置
    static func resolve(_ focus: MonthFocus, in groups: [PurchaseGroup]) -> (group: Int, index: Int)? {
        guard !groups.isEmpty else { return nil }
        if let bookID = focus.bookID {
            for (groupIndex, group) in groups.enumerated() {
                if let index = group.books.firstIndex(where: { $0.id == bookID }) {
                    return (groupIndex, index)
                }
            }
        }
        let groupIndex = groups.firstIndex { $0.id == focus.groupID } ?? 0
        let count = groups[groupIndex].books.count
        return (groupIndex, min(max(focus.index, 0), max(count - 1, 0)))
    }

    private static func isEarlier(_ lhs: Book, _ rhs: Book) -> Bool {
        let left = lhs.purchaseDate ?? .distantPast
        let right = rhs.purchaseDate ?? .distantPast
        if left != right { return left < right }
        if lhs.addedAt != rhs.addedAt { return lhs.addedAt < rhs.addedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
