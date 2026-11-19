import SwiftUI

/// 購入月別のグリッド表示（J-3 月・J-4 年。F6-7）。
/// 月ごとの見出しを付けた1本の縦スクロールで、スクロールで月を移動する（見出しは上に固定）。
/// 月は横3列（表紙＋題名）、ピンチインで年ごとの見出し＋1行5冊の表紙だけのグリッドに、ピンチアウトで月に戻る。
/// 月のグリッドは長押しでメニュー（詳細・別の棚へ移動・削除。I-2 と同じ）
struct MonthGridView: View {
    let groups: [PurchaseGroup]
    let period: PurchasePeriod
    let store: ImageStore
    let onTapBook: (Book, PurchaseGroup) -> Void
    /// 長押し（本・セルの画面上の位置）。月のグリッドだけ
    let onLongPress: (Book, CGRect) -> Void
    let onPinch: (PurchasePeriod) -> Void
    /// 右上の共有マーク（T11）。いちばん上に見えている月（年）を共有する
    let onShare: (PurchaseGroup) -> Void
    /// 画面に見えているまとまり（共有するまとまりを決める）
    @State private var visible: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                    Section {
                        grid(group, start: start(of: groupIndex))
                            .padding(.bottom, 12)
                            .onScrollVisibilityChange(threshold: 0.05) { isVisible in
                                if isVisible {
                                    visible.insert(group.id)
                                } else {
                                    visible.remove(group.id)
                                }
                            }
                    } header: {
                        header(group)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // 月と年を切り替えたら先頭（いちばん新しいまとまり）から見せる
        .id(period)
        // 見出しを上から少し下げた位置に固定する（ジャンル別の棚の名前と同じ高さ。上の余白には本を出さない）
        .padding(.top, 30)
        .overlay(alignment: .topTrailing) {
            MonthShareButton {
                // 見えているうちいちばん上（新しい）のまとまり
                if let group = groups.first(where: { visible.contains($0.id) }) ?? groups.first {
                    onShare(group)
                }
            }
            .padding(.trailing, 22)
            .padding(.top, 40)
        }
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.05)
                .onEnded { value in
                    if value.magnification < 0.85 {
                        onPinch(.year)
                    } else if value.magnification > 1.15 {
                        onPinch(.month)
                    }
                }
        )
        // 子（右上の共有マーク）の識別子を残す（T11）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monthGrid")
    }

    /// まとまりの最初の本の通し番号（識別子 grid.book.n を全体で重ならないようにする）
    private func start(of groupIndex: Int) -> Int {
        groups[..<groupIndex].reduce(0) { $0 + $1.books.count }
    }

    /// 上に固定する見出し（「2026年11月」と冊数。J-3・J-4）
    private func header(_ group: PurchaseGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(group.displayTitle)
                .font(BookshelfStyle.sans(22, .medium, relativeTo: .title2))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .lineLimit(1)
            Text(String(appLocalized: "\(group.books.count)冊"))
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .padding(.top, 2)
            Spacer(minLength: 70)
        }
        .padding(.leading, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BookshelfStyle.background)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("monthGrid.header.\(group.id)")
        .accessibilityAction(named: period == .month ? "年にまとめる" : "月に戻す") {
            onPinch(period == .month ? .year : .month)
        }
    }

    @ViewBuilder
    private func grid(_ group: PurchaseGroup, start: Int) -> some View {
        if period == .month {
            // 横3列（I-1 と同じ寸法: 列の間 12、行の間 14、左右 20）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(Array(group.books.enumerated()), id: \.element.id) { offset, book in
                    MonthGridCell(
                        book: book, index: start + offset, store: store,
                        onTap: { onTapBook(book, group) },
                        onLongPress: { onLongPress(book, $0) })
                }
            }
            .padding(.horizontal, 20)
        } else {
            // 1行5冊の表紙だけ（J-4）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(Array(group.books.enumerated()), id: \.element.id) { offset, book in
                    MonthCoverCell(book: book, index: start + offset, store: store) {
                        onTapBook(book, group)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// 月のグリッドの1冊（I-1 のセルと同じ見た目）。長押しでメニューを出すため、画面上の位置を覚えておく
private struct MonthGridCell: View {
    let book: Book
    let index: Int
    let store: ImageStore
    let onTap: () -> Void
    let onLongPress: (CGRect) -> Void
    @State private var frame: CGRect = .zero

    var body: some View {
        GridCellContent(
            item: ShelfBookItem(
                id: book.id, title: book.title, coverRevision: CoverImageCache.shared.revision(for: book.id)),
            index: index, store: store,
            onMenu: { onLongPress(frame) }
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress(frame)
        }
    }
}

/// 年のグリッドの1冊（表紙だけ。縦横比のまま、枠の下にそろえる）
private struct MonthCoverCell: View {
    static let coverHeight: CGFloat = 92

    let book: Book
    let index: Int
    let store: ImageStore
    let onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(BookshelfStyle.fill)
                    .aspectRatio(0.7, contentMode: .fit)
            }
        }
        .frame(height: Self.coverHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(book.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("grid.book.\(index)")
        .task(id: book.id) {
            image = CoverImageCache.shared.cachedThumbnail(for: book.id)
            if image == nil {
                image = await CoverImageCache.shared.thumbnail(for: book.id, in: store)
            }
        }
    }
}
