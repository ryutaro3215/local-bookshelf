import Foundation
import SwiftData
import SwiftUI
import os

/// 「購入した」を取り消すための記録（E-8 の「取り消す」で、所持状況・購入日・棚の中の位置を元に戻す）
struct PurchaseRecord {
    let book: Book
    /// 本の ID（本が削除されたあとでも、本のデータを読まずに確かめられるよう控える。N-060 と同じ考え方）
    let bookID: UUID
    let shelf: Shelf?
    let sortOrder: Int
    let ownership: Ownership
    let purchaseDate: Date?
}

extension LibraryStore {
    /// 「購入した」（§10.3）。所持状況を「購入済み」にし、購入日を今日にして、そのジャンルの棚の末尾に並べる。
    /// 戻り値で `undoPurchase` を呼ぶと元に戻る
    @discardableResult
    func purchase(_ book: Book, now: Date = .now) throws -> PurchaseRecord {
        guard try containsBook(id: book.id), !book.isDeleted else { throw LibraryError.bookNotFound }
        let record = PurchaseRecord(
            book: book, bookID: book.id, shelf: book.shelf, sortOrder: book.sortOrder, ownership: book.ownership,
            purchaseDate: book.purchaseDate)
        guard book.ownership == .wanted else { return record }
        // ジャンルの無い本は未分類に並べる（通常は起きない。買いたい本もジャンルを持つ）
        let shelf = try book.shelf ?? unsortedShelf()
        book.sortOrder = nextSortOrder(in: shelf, excluding: book)
        book.shelf = shelf
        book.ownership = .owned
        book.purchaseDate = calendar.startOfDay(for: now)
        try commit()
        return record
    }

    /// 「購入した」を取り消す。所持状況・購入日・ジャンル・並び順の値を元に戻す。
    /// 本・元の棚が削除されていたら何も変えずに投げる（N-060 と同じ守り）
    func undoPurchase(_ record: PurchaseRecord) throws {
        let book = record.book
        guard try containsBook(id: record.bookID), !book.isDeleted, book.modelContext != nil else {
            throw LibraryError.bookNotFound
        }
        let shelf = try record.shelf ?? unsortedShelf()
        guard try shelves().contains(where: { $0.persistentModelID == shelf.persistentModelID }) else {
            throw LibraryError.shelfNotFound
        }
        // その間に同じ値の本が入っていたら、その本から後ろを1つずつずらして元の位置を空ける
        let others = shelf.books.filter { $0.id != book.id }
        if others.contains(where: { $0.sortOrder == record.sortOrder }) {
            for other in others where other.sortOrder >= record.sortOrder {
                other.sortOrder += 1
            }
        }
        book.shelf = shelf
        book.sortOrder = record.sortOrder
        book.ownership = record.ownership
        book.purchaseDate = record.purchaseDate
        try commit()
    }
}

/// 詳細画面の「購入した」と、その後の通知（E-8「購入済みにしました／取り消す」）の状態
@MainActor
@Observable
final class PurchaseAction {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let record: PurchaseRecord?
    }

    /// 通知を出しておく時間（棚の移動の通知と同じ）
    static let toastDuration: Duration = .seconds(5)
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Purchase")

    var toast: Toast?

    /// 「購入した」を押した。成功したら true
    func purchase(_ book: Book, store: LibraryStore) -> Bool {
        do {
            let record = try store.purchase(book)
            toast = Toast(message: "購入済みにしました", record: record)
            return true
        } catch {
            Self.logger.error("購入済みにできない: \(error.localizedDescription, privacy: .public)")
            toast = Toast(message: "購入済みにできませんでした", record: nil)
            return false
        }
    }

    /// 「取り消す」。成功したら true
    func undo(_ toast: Toast, store: LibraryStore) -> Bool {
        guard let record = toast.record else { return false }
        self.toast = nil
        do {
            try store.undoPurchase(record)
            return true
        } catch {
            Self.logger.error("購入を取り消せない: \(error.localizedDescription, privacy: .public)")
            self.toast = Toast(message: "取り消せませんでした", record: nil)
            return false
        }
    }
}

/// 「購入した」のあとの通知（E-8。INK の地・角 16・高さ 48。右に下線つきの「取り消す」。D-3 のトーストと同じ形）
struct PurchaseToastView: View {
    let toast: PurchaseAction.Toast
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(toast.message)
                .font(BookshelfStyle.sans(15))
                .tracking(0.5)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .accessibilityIdentifier("toast.message")
            Spacer(minLength: 12)
            if toast.record != nil {
                Button(action: onUndo) {
                    Text("取り消す")
                        .font(BookshelfStyle.sans(15, .medium))
                        .tracking(0.5)
                        .underline()
                        .foregroundStyle(Color.white)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toast.undo")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.ink))
        .shadow(color: .black.opacity(0.18), radius: 9, x: 0, y: 6)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}
