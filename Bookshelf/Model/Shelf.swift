import Foundation
import SwiftData

/// 棚の種類。ユーザーのジャンルか、最初からあるシステム棚か（requirements §10.2・§10.3）。
enum ShelfKind: String, Codable, Sendable {
    /// ジャンル（初期ジャンル・ユーザーが作ったジャンル）
    case genre
    /// 買いたい本（所持状況が「買いたい」の本を集めて見せる棚。本の入れ物ではない）
    case wishlist
    /// 未分類（どのジャンルにも入っていない本の置き場）
    case unsorted
}

/// ジャンル（＝棚）。
@Model
final class Shelf {
    /// 表示名（日本語、またはユーザーが付けた名前）
    var name: String
    /// 初期ジャンル・システム棚の英語名。ユーザーが作ったジャンルは nil（翻訳しない）
    var nameEn: String?
    /// 区分の ID（`GenreCategory.id`）
    var categoryID: String
    /// 棚どうしの並び順（小さいほど前）
    var sortOrder: Int
    var kindRaw: String

    @Relationship(deleteRule: .nullify, inverse: \Book.shelf)
    var books: [Book] = []

    init(name: String, nameEn: String? = nil, categoryID: String, sortOrder: Int, kind: ShelfKind = .genre) {
        self.name = name
        self.nameEn = nameEn
        self.categoryID = categoryID
        self.sortOrder = sortOrder
        self.kindRaw = kind.rawValue
    }

    var kind: ShelfKind {
        ShelfKind(rawValue: kindRaw) ?? .genre
    }

    /// 買いたい本・未分類（削除も名前変更もできない）
    var isSystem: Bool {
        kind != .genre
    }
}
