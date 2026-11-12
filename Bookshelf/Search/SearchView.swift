import SwiftData
import SwiftUI

/// 検索（E-4 結果・E-5 0件。requirements F7・Figma 54:32099・49:24501）。
/// 閲覧画面の下部バーの検索欄を押すと開き、検索欄は画面の上に移る。入力に合わせて、全ジャンルの購入済みの本を
/// 題名とよみの部分一致で絞り込み、題名の一致した部分を強調する。「買いたい」の本は出さない（F7-4）。
/// 結果を押すと本の詳細へ。「キャンセル」で閲覧画面に戻る
struct SearchView: View {
    let images: ImageStore
    let onOpen: (Book) -> Void
    let onCancel: () -> Void

    /// 購入済みの本（検索はこの一覧に対して行う。編集・購入で変わると結果も変わる）
    @Query(filter: #Predicate<Book> { $0.ownershipRaw == "owned" }) private var ownedBooks: [Book]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let results = LibraryStore.search(ownedBooks, matching: query)
        VStack(spacing: 0) {
            searchBar
                .padding(.top, 4)
            if trimmedQuery.isEmpty {
                Spacer(minLength: 0)
            } else if results.isEmpty {
                emptyResult
            } else {
                resultList(results)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { focused = true }
    }

    // MARK: 上の検索欄

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(BookshelfStyle.sub)
                    .accessibilityHidden(true)
                TextField(
                    "", text: $query,
                    prompt: Text("題名・よみで検索").foregroundStyle(BookshelfStyle.sub)
                )
                .font(BookshelfStyle.sans(17))
                .foregroundStyle(BookshelfStyle.ink)
                .tint(BookshelfStyle.ink)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { focused = false }
                .accessibilityLabel("題名・よみで検索")
                .accessibilityIdentifier("search.field")
                if !query.isEmpty {
                    Button {
                        query = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(BookshelfStyle.faint)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("検索語を消す")
                    .accessibilityIdentifier("search.clear")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 44)
            .background(Capsule().fill(BookshelfStyle.fill))
            Button("キャンセル") {
                focused = false
                onCancel()
            }
            .font(BookshelfStyle.sans(15))
            .foregroundStyle(BookshelfStyle.ink)
            .frame(minHeight: 44)
            .accessibilityIdentifier("search.cancel")
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
    }

    // MARK: 結果（E-4）

    private func resultList(_ results: [Book]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("\(results.count)件（題名・よみの一部に一致）")
                    .font(BookshelfStyle.sans(12))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("search.count")
                ForEach(Array(results.enumerated()), id: \.element.id) { index, book in
                    SearchResultRow(
                        book: book, query: query, images: images, showsSeparator: index < results.count - 1
                    ) {
                        focused = false
                        onOpen(book)
                    }
                    .accessibilityIdentifier("search.result.\(index)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: 0件（E-5）

    private var emptyResult: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(BookshelfStyle.sub)
                .frame(width: 56, height: 56)
                .background(Circle().fill(BookshelfStyle.fill))
                .accessibilityHidden(true)
            Text("「\(trimmedQuery)」に一致する本はありません")
                .font(BookshelfStyle.sans(15, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .accessibilityIdentifier("search.empty.title")
            Text("題名やよみの一部だけでも検索できます")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .accessibilityIdentifier("search.empty.hint")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 94)
        .frame(maxWidth: .infinity)
    }
}

/// 検索結果の1行（表紙・題名〔一致を強調〕・ジャンルと購入日・›）。VoiceOver では題名を読み上げる（N5）
struct SearchResultRow: View {
    let book: Book
    let query: String
    let images: ImageStore
    let showsSeparator: Bool
    let onTap: () -> Void
    @State private var cover: UIImage?

    /// 強調の地（design-brief §3「検索結果の強調」）
    static let highlight = Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                coverView
                    .frame(width: 48, height: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.highlighted(book.title, query: query))
                        .font(BookshelfStyle.serif(17, relativeTo: .headline))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detailLine)
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.sub)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BookshelfStyle.faint)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 4)
            .frame(minHeight: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(BookshelfStyle.panelLine)
                    .frame(height: 1)
                    .padding(.leading, 64)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(book.title)
        .accessibilityValue(detailLine)
        .accessibilityAddTraits(.isButton)
        .task(id: book.id) {
            cover = CoverImageCache.shared.cachedThumbnail(for: book.id)
            if cover == nil {
                cover = await CoverImageCache.shared.thumbnail(for: book.id, in: images)
            }
        }
    }

    @ViewBuilder private var coverView: some View {
        if let cover {
            Image(uiImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(maxWidth: 48, maxHeight: 64)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(BookshelfStyle.fill)
                .frame(width: 44, height: 64)
        }
    }

    /// 「哲学・思想・購入日 2026.10.20」
    private var detailLine: String {
        let shelf = book.shelf?.name ?? "未分類"
        guard let date = book.purchaseDate else { return shelf }
        return "\(shelf)・購入日 \(BookDates.format(date))"
    }

    /// 題名の一致した部分に強調の地を付ける
    static func highlighted(_ title: String, query: String) -> AttributedString {
        let ranges = SearchText.matchRanges(of: query, in: title)
        var result = AttributedString()
        var cursor = title.startIndex
        for range in ranges {
            result += AttributedString(String(title[cursor..<range.lowerBound]))
            var match = AttributedString(String(title[range]))
            match.backgroundColor = highlight
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(String(title[cursor...]))
        return result
    }
}
