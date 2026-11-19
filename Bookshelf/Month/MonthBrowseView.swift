import SwiftUI

/// 購入月別の棚表示（J-1 月・J-2 年。F6-7）。
/// その月（年）に購入した本を購入日の古い順に横に並べ、横スワイプで本をめくり、縦スワイプで月（年）をかえる。
/// ピンチインで年にまとめ、ピンチアウトで月に戻る。上の月・年の名前には「▾」を付けず、押しても一覧は開かない。
/// 並びは購入日順で固定（手での並べ替えはしない）。長押しで選んだ本は、別の棚へ移動・削除できる
struct MonthBrowseView: View {
    let groups: [PurchaseGroup]
    /// 今のまとまりの番号と、その中の中央の本の番号
    let groupIndex: Int
    let index: Int
    let store: ImageStore
    /// 長押しで選んでいる本（今のまとまりの本のときだけ使う）
    let selection: ShelfEditing.Selection?
    /// 月（年）が入ってくる向き
    let edge: Edge
    let onCenterChange: (Int) -> Void
    /// 縦スワイプ（+1 = 次（古い）のまとまり・上へ、-1 = 前（新しい）のまとまり・下へ）
    let onMoveGroup: (Int) -> Void
    /// 年の表示で、下の月の名前を押した（その月の最初の本へ）
    let onSelectMonth: (Int) -> Void
    let onTapBook: (Book) -> Void
    let onReorderEvent: (ShelfReorderHandler.Event) -> Void
    let onTapWhileSelected: () -> Void
    let onMoveBook: (Book) -> Void
    let onDeleteBook: (Book) -> Void
    /// ピンチ（年にまとめる・月に戻る）
    let onPinch: (PurchasePeriod) -> Void
    /// 右上の共有マーク（T11。見ている本の日と、この月（年）から範囲を選ぶ）
    let onShare: () -> Void

    private var group: PurchaseGroup { groups[groupIndex] }

    var body: some View {
        let group = group
        let selection = selection.flatMap { selected in
            group.books.contains { $0.id == selected.bookID } ? selected : nil
        }
        VStack(spacing: 0) {
            MonthHeader(
                group: group,
                onMoveGroup: onMoveGroup,
                onPinch: onPinch,
                onShare: onShare)
            ZStack {
                VStack(spacing: 0) {
                    carousel(group, selection: selection)
                    info(group, selection: selection)
                    Spacer(minLength: 0)
                }
                .id(group.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: edge).combined(with: .opacity),
                        removal: .move(edge: edge == .bottom ? .top : .bottom).combined(with: .opacity)))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .overlay(alignment: .topTrailing) {
                ShelfIndicator(
                    count: groups.count, index: groupIndex,
                    label: group.period == .month ? "月の位置" : "年の位置",
                    onStep: onMoveGroup
                )
                .padding(.trailing, 26)
                .padding(.top, 388)
            }
        }
        // 指を閉じる（ピンチイン）で年、開く（ピンチアウト）で月（写真アプリと同じ向き）
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
    }

    // MARK: - 書影の並び

    private func carousel(_ group: PurchaseGroup, selection: ShelfEditing.Selection?) -> some View {
        ZStack {
            // 中央の表紙の下に、床に落ちる柔らかい影（ジャンル別の棚表示と同じ）
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.07), Color.black.opacity(0)], center: .center,
                        startRadius: 0, endRadius: 150)
                )
                .frame(width: 300, height: 26)
                .offset(y: 140)
            ShelfCollectionView(
                items: group.books.map {
                    ShelfBookItem(
                        id: $0.id, title: $0.title, coverRevision: CoverImageCache.shared.revision(for: $0.id))
                },
                // 購入月別には末尾の空き枠を出さない（登録先のジャンルが決まらないため）
                showsSlot: false,
                centerIndex: index,
                store: store,
                onCenterChange: onCenterChange,
                onTapBook: { position in
                    if group.books.indices.contains(position) { onTapBook(group.books[position]) }
                },
                onTapSlot: {},
                onVerticalSwipe: onMoveGroup,
                selectedIndex: selection?.to,
                onReorderEvent: onReorderEvent,
                onTapWhileSelected: onTapWhileSelected)
            if let selection, let book = group.books.first(where: { $0.id == selection.bookID }) {
                SelectionArrows(
                    selection: selection, allowsReorder: false, count: group.books.count,
                    onStep: { _ in },
                    onMove: { onMoveBook(book) },
                    onDelete: { onDeleteBook(book) }
                )
                .offset(y: -PinLayout.liftHeight)
            }
        }
        .frame(height: 324)
        .padding(.top, 64)
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    // MARK: - 本の情報（題名 → ジャンル・購入日 → 位置。年は下に月の並び）

    @ViewBuilder
    private func info(_ group: PurchaseGroup, selection: ShelfEditing.Selection?) -> some View {
        VStack(spacing: 6) {
            if group.books.indices.contains(index) {
                let book = group.books[index]
                Text(book.title)
                    .font(BookshelfStyle.serif(20, relativeTo: .title3))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .accessibilityIdentifier("shelf.bookTitle")
                if let selection {
                    SelectionInfo(selection: selection, allowsReorder: false, count: group.books.count)
                        .padding(.top, 6)
                } else {
                    Text(meta(of: book))
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.sub)
                        .lineLimit(1)
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("shelf.bookMeta")
                    Text("\(index + 1) / \(group.books.count)")
                        .font(BookshelfStyle.sans(11))
                        .tracking(1)
                        .foregroundStyle(BookshelfStyle.faint)
                        .padding(.top, 2)
                        .accessibilityIdentifier("shelf.position")
                    if group.period == .year {
                        MonthTabs(
                            months: MonthGrouping.months(in: group),
                            current: MonthGrouping.month(of: book),
                            onSelect: onSelectMonth
                        )
                        .padding(.top, 22)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, selection == nil ? 0 : 17)
        .contentShape(Rectangle())
        .onTapGesture {
            if selection != nil { onTapWhileSelected() }
        }
    }

    /// 「哲学・思想・2026.10.20 購入」（design-brief §3「本の情報」）
    private func meta(of book: Book) -> String {
        let genre = book.shelf?.displayName ?? InitialGenres.unsortedDisplayName
        guard let date = book.purchaseDate else { return genre }
        return String(appLocalized: "\(genre)・\(BookDates.format(date)) 購入")
    }
}

// MARK: - 上（月・年の名前と冊数・共有マーク）

/// 購入月別の上部（J-1・J-2）。名前はゴシック（Noto Sans JP 500）で、「▾」は付けず押せない
struct MonthHeader: View {
    let group: PurchaseGroup
    let onMoveGroup: (Int) -> Void
    let onPinch: (PurchasePeriod) -> Void
    let onShare: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 4) {
                Text(group.displayTitle)
                    .font(BookshelfStyle.sans(22, .medium, relativeTo: .title2))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .lineLimit(1)
                    .frame(minHeight: 32)
                Text(String(appLocalized: "\(group.books.count)冊"))
                    .font(BookshelfStyle.sans(12))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
            }
            .padding(.horizontal, 70)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.displayTitle)
            .accessibilityValue(String(appLocalized: "\(group.books.count)冊"))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("month.title")
            // ピンチ・縦スワイプの代わり（VoiceOver。N5）
            .accessibilityAction(named: group.period == .month ? "前の月" : "前の年") { onMoveGroup(1) }
            .accessibilityAction(named: group.period == .month ? "次の月" : "次の年") { onMoveGroup(-1) }
            .accessibilityAction(named: group.period == .month ? "年にまとめる" : "月に戻す") {
                onPinch(group.period == .month ? .year : .month)
            }
            HStack {
                Spacer()
                MonthShareButton(action: onShare)
            }
            .padding(.trailing, 22)
            .offset(y: -4)
        }
        .padding(.top, 44)
    }
}

/// 共有マーク（F8-5。購入月別では「この日／この月」・年では「この日／この年」を選んでから共有する。T11）
struct MonthShareButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(BookshelfStyle.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(BookshelfStyle.fill))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("共有")
        .accessibilityIdentifier("shelf.share")
    }
}

// MARK: - 年の表示の月の並び（J-2「8月｜9月｜10月｜11月」）

/// その年に本のある月を並べ、今の本の月を濃くする。押すとその月の最初の本へ移る
struct MonthTabs: View {
    let months: [Int]
    let current: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(months.enumerated()), id: \.element) { offset, month in
                if offset > 0 {
                    Rectangle()
                        .fill(BookshelfStyle.line)
                        .frame(width: 1, height: 12)
                }
                Button {
                    onSelect(month)
                } label: {
                    Text(PurchaseGroup.monthLabel(month))
                        .font(BookshelfStyle.sans(13, month == current ? .medium : .regular))
                        .tracking(0.5)
                        .foregroundStyle(month == current ? BookshelfStyle.ink : BookshelfStyle.faint)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(month == current ? .isSelected : [])
                .accessibilityIdentifier("month.tab.\(month)")
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 購入済みの本が無いとき

/// 購入月別で、購入済みの本が1冊もないとき（Figma に無い画面。閲覧画面の空の表示に合わせた）
struct MonthEmptyView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("購入した本はまだありません")
                .font(BookshelfStyle.sans(18, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .accessibilityIdentifier("month.emptyTitle")
            Text("購入済みの本が、買った月ごとに並びます。")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("month.empty")
    }
}
