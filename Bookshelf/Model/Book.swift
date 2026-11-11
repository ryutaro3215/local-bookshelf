import Foundation
import SwiftData

/// 所持状況（requirements §10.3）。ジャンルとは独立した軸。
enum Ownership: String, Codable, Sendable {
    /// 購入済み
    case owned
    /// 買いたい
    case wanted
}

/// 本（requirements §10.1）。
@Model
final class Book {
    /// 表紙画像のファイル名にも使う ID（重複させない）
    @Attribute(.unique) var id: UUID
    /// 題名（1〜200文字。制御文字なし）
    var title: String
    /// 題名のよみ（ひらがな）。画面には出さず、題名順の並べ替えと検索に使う（F7-1）
    var yomi: String
    /// データ追加日（登録した日時。編集不可）
    var addedAt: Date
    var ownershipRaw: String
    /// 購入日（購入済みの本だけ。日付のみ）
    var purchaseDate: Date?
    /// ジャンル内の並び順（小さいほど前）
    var sortOrder: Int
    /// 所属するジャンル（買いたい本の棚には所属させない）
    var shelf: Shelf?

    init(
        id: UUID = UUID(),
        title: String,
        yomi: String,
        addedAt: Date,
        ownership: Ownership,
        purchaseDate: Date?,
        sortOrder: Int,
        shelf: Shelf?
    ) {
        self.id = id
        self.title = title
        self.yomi = yomi
        self.addedAt = addedAt
        self.ownershipRaw = ownership.rawValue
        self.purchaseDate = purchaseDate
        self.sortOrder = sortOrder
        self.shelf = shelf
    }

    var ownership: Ownership {
        get { Ownership(rawValue: ownershipRaw) ?? .owned }
        set { ownershipRaw = newValue.rawValue }
    }
}
