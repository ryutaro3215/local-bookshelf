import Foundation
import SwiftData
import Testing

@testable import Bookshelf

/// plan.md T13 の acceptance（MonthGroupingTests ①〜③）と、月・年を切り替えたときに同じ本を見せるための位置の求め方。
/// 題名はすべて架空
@MainActor
struct MonthGroupingTests {
    let store: LibraryStore
    let calendar = Calendar.current

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MonthGroupingTests-\(UUID().uuidString)", isDirectory: true)
        store = LibraryStore(container: container, images: ImageStore(directory: folder))
        try store.seedIfNeeded()
    }

    func genre(_ name: String) throws -> Shelf {
        try #require(try store.shelves().first(where: { $0.name == name }))
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    /// 購入日を指定して購入済みの本を足す（購入日はデータ追加日の日付になる）
    @discardableResult
    func add(_ title: String, _ year: Int, _ month: Int, _ day: Int, genre name: String = "小説") throws -> Book {
        try store.addBook(title: title, shelf: genre(name), now: date(year, month, day))
    }

    func pair(_ value: (group: Int, index: Int)?) -> [Int]? {
        value.map { [$0.group, $0.index] }
    }

    func allBooks() throws -> [Book] {
        try store.context.fetch(FetchDescriptor<Book>())
    }

    @Test("① 購入日で月ごとにまとまり、中の並びは購入日の古い順（1日→31日）。まとまりは新しい順")
    func groupsByMonthOldestFirst() throws {
        try add("冬の観測所", 2026, 10, 31)
        try add("灰色の標本箱", 2026, 10, 1)
        try add("静かな温室", 2026, 11, 3, genre: "エッセイ")
        try add("遠い灯台の記録", 2026, 10, 15, genre: "哲学・思想")
        try add("青い回廊", 2025, 12, 24)
        let groups = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        #expect(groups.map(\.title) == ["2026年11月", "2026年10月", "2025年12月"])
        // ジャンルをまたいで、その月に買った本がそろう
        #expect(groups[1].books.map(\.title) == ["灰色の標本箱", "遠い灯台の記録", "冬の観測所"])
        #expect(groups[0].books.map(\.title) == ["静かな温室"])
        #expect(groups.allSatisfy { $0.period == .month && $0.month != nil })
    }

    @Test("① 年ごとにまとめると、その年の本が購入日の古い順に1列に並ぶ")
    func groupsByYearOldestFirst() throws {
        try add("冬の観測所", 2026, 11, 2)
        try add("灰色の標本箱", 2026, 1, 9)
        try add("遠い灯台の記録", 2026, 10, 20)
        try add("青い回廊", 2025, 3, 1)
        try add("小さな地図", 2025, 12, 31)
        let groups = MonthGrouping.groups(of: try allBooks(), by: .year, calendar: calendar)
        #expect(groups.map(\.title) == ["2026年", "2025年"])
        #expect(groups[0].books.map(\.title) == ["灰色の標本箱", "遠い灯台の記録", "冬の観測所"])
        #expect(groups[1].books.map(\.title) == ["青い回廊", "小さな地図"])
        #expect(MonthGrouping.months(in: groups[0], calendar: calendar) == [1, 10, 11])
    }

    @Test("① 同じ日に買った本は、登録した順に並ぶ")
    func sameDayKeepsRegistrationOrder() throws {
        try store.addBook(title: "眠る郵便局", shelf: genre("小説"), now: date(2026, 10, 5, hour: 9))
        try store.addBook(title: "白い植物園", shelf: genre("小説"), now: date(2026, 10, 5, hour: 18))
        try store.addBook(title: "古い時計", shelf: genre("小説"), now: date(2026, 10, 5, hour: 13))
        let groups = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        #expect(groups.first?.books.map(\.title) == ["眠る郵便局", "古い時計", "白い植物園"])
    }

    @Test("② 本のない月・年は含まれない")
    func emptyPeriodsAreExcluded() throws {
        try add("冬の観測所", 2026, 11, 2)
        try add("灰色の標本箱", 2026, 8, 9)
        try add("青い回廊", 2023, 4, 1)
        let months = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        #expect(months.map(\.title) == ["2026年11月", "2026年8月", "2023年4月"])
        #expect(months.allSatisfy { !$0.books.isEmpty })
        let years = MonthGrouping.groups(of: try allBooks(), by: .year, calendar: calendar)
        #expect(years.map(\.title) == ["2026年", "2023年"])
        // 本が1冊もなければ、まとまりも無い
        #expect(MonthGrouping.groups(of: [], by: .month, calendar: calendar).isEmpty)
    }

    @Test("③ 「買いたい」の本は含まれない（購入済みにすると、その日の月に入る）")
    func wantedBooksAreExcluded() throws {
        try add("冬の観測所", 2026, 10, 2)
        let wanted = try store.addBook(
            title: "四角い鯨の手帖", shelf: genre("小説"), ownership: .wanted, now: date(2026, 10, 3))
        var groups = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        #expect(groups.flatMap(\.books).map(\.title) == ["冬の観測所"])
        #expect(MonthGrouping.groups(of: try allBooks(), by: .year, calendar: calendar).flatMap(\.books).count == 1)
        // 「買いたい」だけの月は出ない
        let onlyWanted = try store.addBook(
            title: "夜更けの温室", shelf: genre("小説"), ownership: .wanted, now: date(2026, 7, 3))
        groups = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        #expect(groups.map(\.title) == ["2026年10月"])
        try store.setOwnership(wanted, to: .owned, now: date(2026, 11, 1))
        groups = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        #expect(groups.map(\.title) == ["2026年11月", "2026年10月"])
        #expect(!groups.flatMap(\.books).contains { $0.id == onlyWanted.id })
    }

    @Test("月と年を切り替えても同じ本を見せる。本が消えたら同じまとまりの近い位置を見せる")
    func focusFollowsTheBook() throws {
        try add("冬の観測所", 2026, 11, 2)
        try add("灰色の標本箱", 2026, 10, 1)
        let target = try add("遠い灯台の記録", 2026, 10, 15)
        try add("青い回廊", 2025, 12, 24)
        let months = MonthGrouping.groups(of: try allBooks(), by: .month, calendar: calendar)
        let years = MonthGrouping.groups(of: try allBooks(), by: .year, calendar: calendar)
        let focus = MonthFocus(groupID: "2026-10", bookID: target.id, index: 1)
        #expect(pair(MonthGrouping.resolve(focus, in: months)) == [1, 1])
        // 2026年: 灰色の標本箱・遠い灯台の記録・冬の観測所
        #expect(pair(MonthGrouping.resolve(focus, in: years)) == [0, 1])
        // 見ていた本が無いときは、同じまとまりの、範囲に収めた位置
        let missing = MonthFocus(groupID: "2025-12", bookID: UUID(), index: 5)
        #expect(pair(MonthGrouping.resolve(missing, in: months)) == [2, 0])
        // まとまりも無いときは最新のまとまりの先頭
        #expect(pair(MonthGrouping.resolve(MonthFocus(), in: months)) == [0, 0])
        #expect(pair(MonthGrouping.resolve(MonthFocus(), in: [])) == nil)
    }
}
