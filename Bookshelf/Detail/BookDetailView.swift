import SwiftUI

/// 日付の表示（Figma の「2026.10.20」。英語表記は T15 で端末ロケールに合わせる）
enum BookDates {
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

/// 本の詳細（E-1 購入済み・E-2 買いたい本。F6-3）。データの表示だけ:
/// 大きな表紙・題名・ジャンル・所持状況・購入日（購入済みの本だけ）。データ追加日は出さない。
/// 「編集」（F6-4）と「購入した」（§10.3）は T9 でつなぐ（今は押しても何もしない）
struct BookDetailView: View {
    let book: Book
    /// 戻る先の棚の名前（左上の「‹ 哲学・思想」）
    let backTitle: String
    let store: ImageStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cover: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    coverView
                        .padding(.top, 10)
                    Text(book.title)
                        .font(BookshelfStyle.serif(22, relativeTo: .title2))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 30)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("detail.title")
                    infoCard
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    if book.ownership == .wanted {
                        purchaseButton
                            .padding(.horizontal, 20)
                            .padding(.top, 26)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: book.id) {
            cover = await CoverImageCache.shared.original(for: book.id, in: store)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .regular))
                    Text(backTitle)
                        .font(BookshelfStyle.serif(15))
                        .tracking(0.5)
                        .lineLimit(1)
                }
                .foregroundStyle(BookshelfStyle.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(backTitle)に戻る")
            .accessibilityIdentifier("detail.back")
            Spacer()
            // 編集（F6-4）は T9
            Button {
            } label: {
                Text("編集")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.edit")
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.top, 4)
    }

    private var coverView: some View {
        Group {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(BookshelfStyle.fill)
                    .aspectRatio(0.7, contentMode: .fit)
            }
        }
        .frame(maxWidth: 260, maxHeight: dynamicTypeSize.isAccessibilitySize ? 200 : 300)
        .accessibilityElement()
        .accessibilityLabel("表紙")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("detail.cover")
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("ジャンル", book.shelf?.name ?? "未分類", serif: true, id: "detail.genre")
            separator
            infoRow(
                "所持状況", book.ownership == .owned ? "購入済み" : "買いたい", serif: false, id: "detail.ownership")
            // 購入日は購入済みの本だけ（F6-3）。データ追加日は出さない
            if book.ownership == .owned, let date = book.purchaseDate {
                separator
                infoRow("購入日", BookDates.format(date), serif: false, id: "detail.purchaseDate")
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
    }

    private var separator: some View {
        Rectangle()
            .fill(BookshelfStyle.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String, serif: Bool, id: String) -> some View {
        let valueText = Text(value)
            .font(serif ? BookshelfStyle.serif(15) : BookshelfStyle.sans(15))
            .tracking(0.3)
            .foregroundStyle(BookshelfStyle.ink)
        let labelText = Text(label)
            .font(BookshelfStyle.sans(14))
            .tracking(0.3)
            .foregroundStyle(BookshelfStyle.sub)
        Group {
            // 文字を大きくしたときは、項目名を値の上に置く（Q-3）
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    labelText
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                HStack {
                    labelText
                    Spacer()
                    valueText
                        .lineLimit(1)
                }
                .frame(minHeight: 52)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// 「購入した」（E-2）。押したときの処理（購入済みにする・通知・取り消し）は T9
    private var purchaseButton: some View {
        VStack(spacing: 14) {
            Button {
            } label: {
                Text("購入した")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(BookshelfStyle.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.purchase")
            Text("購入済みになり \(book.shelf?.name ?? "未分類") の棚に並びます（購入日は今日）")
                .font(BookshelfStyle.sans(12))
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
        }
    }
}
