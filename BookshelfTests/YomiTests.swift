import Testing

@testable import Bookshelf

/// plan.md T2 の acceptance（よみの自動生成）
struct YomiTests {
    @Test("漢字・かなの題名からひらがなのよみを作る")
    func kanjiTitle() {
        #expect(Yomi.make(from: "存在と時間") == "そんざいとじかん")
    }

    @Test("カタカナはひらがなにする")
    func katakanaTitle() {
        #expect(Yomi.make(from: "アーモンド") == "あーもんど")
    }

    @Test("英字はそのまま残す")
    func latinStaysAsIs() {
        #expect(Yomi.make(from: "NARUTO") == "NARUTO")
        #expect(Yomi.make(from: "Swift入門") == "Swiftにゅうもん")
    }

    @Test("空の題名は空のよみ")
    func emptyTitle() {
        #expect(Yomi.make(from: "") == "")
    }
}
