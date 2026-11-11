import SwiftData
import SwiftUI
import os

/// ジャンル管理（F-2a・F-2b・F-4。F4）。区分ごとに全ジャンルを並べ、冊数と「本棚に非表示」（購入済みの本が0冊）を出す。
/// 「編集」で編集モード（F-4）: 左の − で削除（F-5）、名前をタップで名前の変更（F-4b）、右の ≡ をドラッグで区分の中の並び替え。
/// 「ジャンルを追加」（F-3）は区分を選んで、その区分の末尾に追加する。買いたい本・未分類は名前の変更・削除・移動ができない
struct ShelfListView: View {
    let store: LibraryStore
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]
    @Query private var books: [Book]
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showsAdd = false
    @State private var renaming: Shelf?
    @State private var deleting: Shelf?
    @State private var drag: GenreDrag?
    @State private var isScrolled = false
    @State private var addedID: PersistentIdentifier?
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "ShelfList")
    /// 行の高さ（Figma F-2a: 48）。ドラッグで1行分動いたら1つ入れ替える
    static let rowHeight: CGFloat = 48

    var body: some View {
        let groups = self.groups
        let counts = self.counts
        ZStack {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            LargeTitle(text: "ジャンル管理", id: "genres.title")
                            subtitle
                                .padding(.top, 4)
                            addCard
                                .padding(.top, 18)
                            ForEach(groups, id: \.category.id) { group in
                                section(group, counts: counts)
                            }
                            Footnote(
                                text:
                                    "買いたい本は「買いたい」にした本を集めて見せる棚です。\n買いたい本と未分類は、名前の変更・削除・移動が\nできません。ジャンルを削除すると、中の本は未分類に移ります。",
                                color: BookshelfStyle.sub
                            )
                            .accessibilityIdentifier("genres.footnote")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    .scrollDisabled(drag != nil)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top > 56
                    } action: { _, scrolled in
                        withAnimation(.easeOut(duration: 0.15)) { isScrolled = scrolled }
                    }
                    .onChange(of: addedID) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                        addedID = nil
                    }
                }
            }
            if let shelf = renaming {
                GenreRenameDialog(
                    currentName: shelf.name,
                    onCancel: { renaming = nil },
                    onSave: { rename(shelf, to: $0) })
            }
            if let shelf = deleting {
                GenreDeleteDialog(
                    name: shelf.name,
                    bookCount: counts.all[shelf.persistentModelID, default: 0],
                    onCancel: { deleting = nil },
                    onDelete: { delete(shelf) })
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeOut(duration: 0.15), value: renaming?.persistentModelID)
        .animation(.easeOut(duration: 0.15), value: deleting?.persistentModelID)
        .fullScreenCover(isPresented: $showsAdd) {
            GenreAddView(
                categories: InitialGenres.categories.filter { $0.id != InitialGenres.system.id },
                onCancel: { showsAdd = false },
                onAdd: { name, categoryID in add(name: name, categoryID: categoryID) })
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        }
    }

    // MARK: - 上

    private var header: some View {
        NavigationHeader(
            backTitle: isEditing ? nil : "設定", backID: "genres.back", onBack: { dismiss() },
            inlineTitle: isScrolled ? "ジャンル管理" : nil, showsDivider: isScrolled
        ) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isEditing.toggle()
                    drag = nil
                }
            } label: {
                Text(isEditing ? "完了" : "編集")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("genres.edit")
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if isEditing {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .regular))
                Text("名前をタップして変更")
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .regular))
                    .padding(.leading, 4)
                Text("をドラッグして並び替え")
            }
            .font(BookshelfStyle.sans(12))
            .tracking(0.3)
            .foregroundStyle(BookshelfStyle.sub)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("名前をタップして変更、並び替えのつまみをドラッグして並び替え")
            .accessibilityIdentifier("genres.subtitle")
        } else {
            Text("本が入っているジャンルだけが本棚に表示されます")
                .font(BookshelfStyle.sans(12))
                .tracking(0.3)
                .foregroundStyle(BookshelfStyle.sub)
                .accessibilityIdentifier("genres.subtitle")
        }
    }

    /// 「ジャンルを追加」（編集モードでは押せない。F-4）
    private var addCard: some View {
        Button {
            showsAdd = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isEditing ? BookshelfStyle.faint : BookshelfStyle.ink)
                Text("ジャンルを追加")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(isEditing ? BookshelfStyle.faint : BookshelfStyle.ink)
                Spacer()
                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BookshelfStyle.faint)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
        .accessibilityIdentifier("genres.add")
    }

    // MARK: - 区分ごとの一覧

    private func section(_ group: GenreGroup, counts: GenreCounts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: group.category.name)
                .padding(.top, 22)
                .accessibilityIdentifier("genres.category.\(group.category.name)")
            VStack(spacing: 0) {
                ForEach(Array(group.shelves.enumerated()), id: \.element.persistentModelID) { index, shelf in
                    let dragging = drag?.shelfID == shelf.persistentModelID
                    GenreRow(
                        shelf: shelf,
                        count: shelf.kind == .wishlist
                            ? counts.wanted : counts.owned[shelf.persistentModelID, default: 0],
                        isEditing: isEditing,
                        isLast: index == group.shelves.count - 1,
                        isDragging: dragging,
                        onDelete: { deleting = shelf },
                        onRename: { renaming = shelf },
                        onDragChanged: { translation in
                            dragChanged(shelf, index: index, in: group, translation: translation)
                        },
                        onDragEnded: { dragEnded(shelf) },
                        onStep: { step in
                            moveGenre(shelf, to: index + step)
                        }
                    )
                    .offset(y: offset(for: shelf, index: index, in: group))
                    .zIndex(dragging ? 1 : 0)
                    .id(shelf.persistentModelID)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
            .zIndex(drag?.categoryID == group.category.id ? 1 : 0)
        }
        .zIndex(drag?.categoryID == group.category.id ? 1 : 0)
    }

    /// 区分（InitialGenres.categories の順）ごとのジャンル。ジャンルが1つも無い区分は出さない。
    /// 買いたい本・未分類は区分「システム」（画面では「その他」）
    private var groups: [GenreGroup] {
        InitialGenres.categories.compactMap { category in
            let list = shelves.filter { shelf in
                category.id == InitialGenres.system.id
                    ? shelf.isSystem
                    : !shelf.isSystem && Self.categoryID(of: shelf) == category.id
            }
            return list.isEmpty ? nil : GenreGroup(category: category, shelves: list)
        }
    }

    /// 知らない区分の ID のジャンルは「マイジャンル」に入れる（棚を選ぶシートと同じ扱い）
    private static func categoryID(of shelf: Shelf) -> String {
        LibraryStore.categoryRank(shelf.categoryID) == nil ? InitialGenres.myGenres.id : shelf.categoryID
    }

    private var counts: GenreCounts {
        var result = GenreCounts()
        for book in books {
            if book.ownership == .wanted {
                result.wanted += 1
            }
            guard let shelf = book.shelf else { continue }
            result.all[shelf.persistentModelID, default: 0] += 1
            if book.ownership == .owned {
                result.owned[shelf.persistentModelID, default: 0] += 1
            }
        }
        return result
    }

    // MARK: - 並び替え（≡ をドラッグ。F4-2）

    private func dragChanged(_ shelf: Shelf, index: Int, in group: GenreGroup, translation: CGFloat) {
        let count = group.shelves.count
        let target = min(max(index + Int((translation / Self.rowHeight).rounded()), 0), count - 1)
        if let drag, drag.target != target {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        drag = GenreDrag(
            shelfID: shelf.persistentModelID, categoryID: group.category.id, from: index, target: target,
            translation: min(
                max(translation, -CGFloat(index) * Self.rowHeight),
                CGFloat(count - 1 - index) * Self.rowHeight))
    }

    private func dragEnded(_ shelf: Shelf) {
        guard let current = drag, current.shelfID == shelf.persistentModelID else { return }
        // 並びの保存と同時に位置のずらしを外す（行は保存後の並びの位置に来るので、動かさずに置き換える）
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = nil
            if current.target != current.from {
                moveGenre(shelf, to: current.target)
            }
        }
    }

    /// ドラッグ中の行のずらし（持っている行は指に付いて動き、間の行は1行分ずつ譲る）
    private func offset(for shelf: Shelf, index: Int, in group: GenreGroup) -> CGFloat {
        guard let drag, drag.categoryID == group.category.id else { return 0 }
        if drag.shelfID == shelf.persistentModelID { return drag.translation }
        if drag.from < drag.target, index > drag.from, index <= drag.target { return -Self.rowHeight }
        if drag.target < drag.from, index >= drag.target, index < drag.from { return Self.rowHeight }
        return 0
    }

    // MARK: - 保存する操作

    private func moveGenre(_ shelf: Shelf, to index: Int) {
        do {
            try store.moveGenre(shelf, toIndex: index)
        } catch {
            Self.logger.error("ジャンルを並び替えられない: \(error.localizedDescription, privacy: .public)")
            errorMessage = "並び替えを保存できませんでした"
        }
    }

    private func add(name: String, categoryID: String) {
        do {
            let shelf = try store.addGenre(name: name, categoryID: categoryID)
            showsAdd = false
            addedID = shelf.persistentModelID
        } catch {
            Self.logger.error("ジャンルを追加できない: \(error.localizedDescription, privacy: .public)")
            showsAdd = false
            errorMessage = "ジャンルを追加できませんでした"
        }
    }

    private func rename(_ shelf: Shelf, to name: String) {
        renaming = nil
        do {
            try store.renameShelf(shelf, to: name)
        } catch {
            Self.logger.error("ジャンル名を変えられない: \(error.localizedDescription, privacy: .public)")
            errorMessage = "名前を変更できませんでした"
        }
    }

    private func delete(_ shelf: Shelf) {
        deleting = nil
        do {
            try store.deleteShelf(shelf)
        } catch {
            Self.logger.error("ジャンルを削除できない: \(error.localizedDescription, privacy: .public)")
            errorMessage = "ジャンルを削除できませんでした"
        }
    }
}

/// 区分1つ分（見出しとジャンル）
struct GenreGroup {
    let category: GenreCategory
    let shelves: [Shelf]
}

/// 棚ごとの冊数（購入済み・全部）と、「買いたい」の本の数（買いたい本の棚の冊数）
struct GenreCounts {
    var owned: [PersistentIdentifier: Int] = [:]
    var all: [PersistentIdentifier: Int] = [:]
    var wanted = 0
}

/// ≡ をドラッグしている間の状態
struct GenreDrag: Equatable {
    let shelfID: PersistentIdentifier
    let categoryID: String
    let from: Int
    var target: Int
    var translation: CGFloat
}

// MARK: - 1行

/// ジャンルの1行（F-2a・F-4）。購入済みの本が0冊のジャンルは薄い文字で「本棚に非表示」のタグを付ける。
/// 買いたい本・未分類は鍵のアイコンを付け、編集モードでも操作を出さない
struct GenreRow: View {
    let shelf: Shelf
    let count: Int
    let isEditing: Bool
    let isLast: Bool
    let isDragging: Bool
    let onDelete: () -> Void
    let onRename: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    /// VoiceOver の「上へ移動」「下へ移動」（-1 / +1）
    let onStep: (Int) -> Void

    /// 閲覧画面に出ない（購入済みの本が0冊。買いたい本は0冊でも出る。§10.6）
    private var isHidden: Bool {
        shelf.kind != .wishlist && count == 0
    }

    var body: some View {
        HStack(spacing: 0) {
            if shelf.isSystem {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BookshelfStyle.sub)
                    .frame(width: 20)
                    .padding(.trailing, 12)
                    .accessibilityHidden(true)
            } else if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(BookshelfStyle.ink)
                        .frame(width: 32, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(shelf.name)を削除")
                .accessibilityIdentifier("genre.delete.\(shelf.name)")
            }
            if isEditing && !shelf.isSystem {
                Button(action: onRename) {
                    HStack(spacing: 10) {
                        name
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(BookshelfStyle.sub)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(shelf.name)の名前を変更")
                .accessibilityIdentifier("genre.rename.\(shelf.name)")
            } else {
                name
            }
            Spacer(minLength: 8)
            if isHidden && !isEditing {
                Text("本棚に非表示")
                    .font(BookshelfStyle.sans(10))
                    .foregroundStyle(BookshelfStyle.sub)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .overlay(Capsule().stroke(Color(red: 0xD0 / 255, green: 0xD0 / 255, blue: 0xD0 / 255)))
                    .padding(.trailing, 10)
            }
            Text("\(count)冊")
                .font(BookshelfStyle.sans(12))
                .foregroundStyle(isHidden ? BookshelfStyle.faint : BookshelfStyle.sub)
            if isEditing && !shelf.isSystem {
                handle
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, isEditing && !shelf.isSystem ? 4 : 16)
        .frame(height: ShelfListView.rowHeight)
        .background {
            if isDragging {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast && !isDragging {
                CardSeparator()
            }
        }
        .modifier(
            GenreRowAccessibility(
                isContainer: isEditing && !shelf.isSystem, label: shelf.name, value: accessibilityValue)
        )
        .accessibilityIdentifier("genre.row.\(shelf.name)")
    }

    /// 読み上げの値（「3冊」・閲覧画面に出ないときは「0冊、本棚に非表示」・システム棚は「変更できません」）
    private var accessibilityValue: String {
        var parts = ["\(count)冊"]
        if isHidden { parts.append("本棚に非表示") }
        if shelf.isSystem { parts.append("変更できません") }
        return parts.joined(separator: "、")
    }

    private var name: some View {
        Text(shelf.name)
            .font(BookshelfStyle.serif(16))
            .tracking(0.5)
            .foregroundStyle(isHidden ? BookshelfStyle.faint : BookshelfStyle.ink)
            .lineLimit(1)
    }

    /// 並び替えのつまみ（≡）。ドラッグで区分の中の位置を変える。VoiceOver では上へ・下へ移動
    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(BookshelfStyle.faint)
            .frame(width: 52, height: ShelfListView.rowHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation.height) }
                    .onEnded { _ in onDragEnded() }
            )
            .accessibilityElement()
            .accessibilityLabel("\(shelf.name)を並び替え")
            .accessibilityAction(named: "上へ移動") { onStep(-1) }
            .accessibilityAction(named: "下へ移動") { onStep(1) }
            .accessibilityIdentifier("genre.handle.\(shelf.name)")
    }
}

/// 行の読み上げ: 編集モードでは中のボタン（削除・名前の変更・並び替え）を別々に読み、それ以外は1つの要素（名前と冊数）にする
private struct GenreRowAccessibility: ViewModifier {
    let isContainer: Bool
    let label: String
    let value: String

    func body(content: Content) -> some View {
        if isContainer {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(value)
        }
    }
}
