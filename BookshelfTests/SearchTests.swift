import Foundation
import SwiftData
import Testing

@testable import Bookshelf

/// plan.md T10 の acceptance（SearchTests ①〜④）と、検索の文字のそろえ方・強調の範囲・500冊での速さ。
/// 題名はすべて架空（plan の例「存在と時間」は実在の書名なので、同じ性質の架空の題名「灰色の時間割」に置き換えた）
@MainActor
struct SearchTests {
    let store: LibraryStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SearchTests-\(UUID().uuidString)", isDirectory: true)
        store = LibraryStore(container: container, images: ImageStore(directory: folder))
        try store.seedIfNeeded()
    }

    func genre(_ name: String) throws -> Shelf {
        try #require(try store.shelves().first(where: { $0.name == name }))
    }

    func titles(_ query: String) throws -> Set<String> {
        Set(try store.searchOwnedBooks(matching: query).map(\.title))
    }

    @Test("① 題名の部分一致で、全ジャンルの本が見つかる")
    func titlePartialMatch() throws {
        try store.addBook(title: "灰色の時間割", shelf: genre("哲学・思想"))
        try store.addBook(title: "港町の時計台", shelf: genre("小説"))
        try store.addBook(title: "静かな温室", shelf: genre("エッセイ"))
        try store.addBook(title: "夜更けの郵便局", shelf: nil)  // 未分類
        #expect(try titles("時") == ["灰色の時間割", "港町の時計台"])
        #expect(try titles("温室") == ["静かな温室"])
        #expect(try titles("郵便") == ["夜更けの郵便局"])
        #expect(try titles("灯台守").isEmpty)
        // 空・空白だけの検索語は結果なし
        #expect(try titles("").isEmpty)
        #expect(try titles("  ").isEmpty)
    }

    @Test("② よみの部分一致（「じかん」で「灰色の時間割」が見つかる）")
    func yomiPartialMatch() throws {
        let book = try store.addBook(title: "灰色の時間割", shelf: genre("哲学・思想"))
        try store.addBook(title: "静かな温室", shelf: genre("エッセイ"))
        #expect(book.yomi.contains("じかん"))
        #expect(try titles("じかん") == ["灰色の時間割"])
        #expect(try titles("はいいろ") == ["灰色の時間割"])
        // よみだけで一致したときは、題名の強調は無い
        #expect(SearchText.matchRanges(of: "じかん", in: book.title).isEmpty)
    }

    @Test("③ ひらがな・カタカナ、英字の大文字・小文字（全角・半角も）を区別しない")
    func kanaAndCaseInsensitive() throws {
        try store.addBook(title: "ガラス瓶の手帖", shelf: genre("小説"))
        try store.addBook(title: "PAPER COMETS", shelf: genre("小説"))
        try store.addBook(title: "ねむる観測所", shelf: genre("エッセイ"))
        #expect(try titles("がらす") == ["ガラス瓶の手帖"])
        #expect(try titles("ガラス") == ["ガラス瓶の手帖"])
        #expect(try titles("ｶﾞﾗｽ") == ["ガラス瓶の手帖"])  // 半角カナ
        #expect(try titles("ネムル") == ["ねむる観測所"])
        #expect(try titles("paper") == ["PAPER COMETS"])
        #expect(try titles("Comets") == ["PAPER COMETS"])
        #expect(try titles("ＣＯＭＥＴ") == ["PAPER COMETS"])  // 全角英字
        // 濁点は区別する
        #expect(try titles("からす").isEmpty)
    }

    @Test("④ 「買いたい」の本は結果に含まれない")
    func excludesWanted() throws {
        let novel = try genre("小説")
        try store.addBook(title: "冬の灯台の記録", shelf: novel)
        let wanted = try store.addBook(title: "冬の灯台について", shelf: novel, ownership: .wanted)
        #expect(try titles("灯台") == ["冬の灯台の記録"])
        #expect(try titles("ふゆのとうだい") == ["冬の灯台の記録"])
        // 購入済みにすると出る・買いたいに戻すと消える
        try store.setOwnership(wanted, to: .owned)
        #expect(try titles("灯台") == ["冬の灯台の記録", "冬の灯台について"])
        try store.setOwnership(wanted, to: .wanted)
        #expect(try titles("灯台") == ["冬の灯台の記録"])
        // 画面が使う一覧からの検索でも除く
        let all = try store.context.fetch(FetchDescriptor<Book>())
        #expect(LibraryStore.search(all, matching: "灯台").map(\.title) == ["冬の灯台の記録"])
    }

    @Test("並びは購入日の新しい順")
    func newestPurchaseFirst() throws {
        let essay = try genre("エッセイ")
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: .now)
        for (offset, title) in [(-30, "古い地図の手帖"), (-1, "新しい地図の手帖"), (-10, "白い地図の手帖")] {
            let book = try store.addBook(title: title, shelf: essay)
            book.purchaseDate = calendar.date(byAdding: .day, value: offset, to: base)
        }
        try store.commit()
        #expect(try store.searchOwnedBooks(matching: "地図").map(\.title) == ["新しい地図の手帖", "白い地図の手帖", "古い地図の手帖"])
    }

    @Test("題名の強調の範囲は、そろえる前の題名の文字を指す")
    func highlightRanges() {
        let title = "灰色のガラス瓶とガラス"
        let ranges = SearchText.matchRanges(of: "がらす", in: title)
        #expect(ranges.map { String(title[$0]) } == ["ガラス", "ガラス"])
        let latin = "Paper ＣＯＭＥＴＳ"
        #expect(SearchText.matchRanges(of: "comets", in: latin).map { String(latin[$0]) } == ["ＣＯＭＥＴＳ"])
        #expect(SearchText.matchRanges(of: "", in: title).isEmpty)
    }

    @Test("500冊でも1回の検索が速い（N1 の目安。入力のたびに検索するため）")
    func fastWithFiveHundredBooks() throws {
        let novel = try genre("小説")
        let heads = ["灰色の", "遠い", "静かな", "四角い", "夜更けの", "小さな", "白い", "長い", "眠る", "青い"]
        let bodies = ["標本箱", "観測所", "図書係", "灯台", "時計", "鯨", "温室", "地図", "回廊", "郵便局"]
        let tails = ["の記録", "について", "と午後", "の手帖", "の問題"]
        for index in 0..<500 {
            let title = heads[index % 10] + bodies[(index / 10) % 10] + tails[(index / 100) % 5]
            store.context.insert(
                Book(
                    title: title, yomi: Yomi.make(from: title), addedAt: .now, ownership: .owned,
                    purchaseDate: .now, sortOrder: index, shelf: novel))
        }
        try store.commit()
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            for query in ["と", "とけい", "トケイ", "灯台", "x"] {
                count += (try? store.searchOwnedBooks(matching: query).count) ?? -1000
            }
        }
        #expect(count > 0)
        // 5回で 0.5 秒以内（1回 0.1 秒以内）
        #expect(elapsed < .milliseconds(500), "500冊の検索5回に \(elapsed)")
    }
}
