import SwiftData
import SwiftUI

/// 閲覧画面に出す棚1つ分（棚と、そこに並べる本）
struct BrowseShelf: Identifiable {
    let shelf: Shelf
    let books: [Book]
    var id: PersistentIdentifier { shelf.persistentModelID }
    var isWishlist: Bool { shelf.kind == .wishlist }
    /// 末尾の空き枠（F1-6 B）。買いたい本の棚には出さない
    var showsSlot: Bool { !isWishlist }
    var items: [ShelfBookItem] {
        books.map {
            ShelfBookItem(id: $0.id, title: $0.title, coverRevision: CoverImageCache.shared.revision(for: $0.id))
        }
    }
    /// 長押しで並べ替えられるか（買いたい本は登録した順に並ぶので並べ替えない）
    var allowsReorder: Bool { !isWishlist }

    /// 並べ替えの途中の並び（プレビュー）を当てた棚
    func with(books: [Book]) -> BrowseShelf {
        BrowseShelf(shelf: shelf, books: books)
    }
}

/// 詳細画面へ移るときの行き先
struct DetailRoute: Hashable {
    let bookID: UUID
    let backTitle: String
}

/// 閲覧画面（アプリの最初の画面。F6・F6-8・Figma 41:20902）。
/// 上: 棚の名前▾と冊数・右上の共有マーク。中: 棚表示（横で本・縦で棚）かグリッド表示（縦スクロール・左右で棚）。
/// 下部バー: 表示・検索欄・＋
struct ShelfScreen: View {
    let environment: AppEnvironment
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]
    @Query(sort: \Book.sortOrder) private var books: [Book]

    @State private var currentID: PersistentIdentifier?
    /// 棚ごとの中央の位置（棚をかえて戻ってきたときに続きから見せる）
    @State private var positions: [PersistentIdentifier: Int] = [:]
    @State private var mode: DisplayMode = .shelf
    /// 棚をかえたときに、新しい棚が入ってくる向き
    @State private var shelfEdge: Edge = .bottom
    @State private var showsPicker = false
    @State private var showsMenu = false
    /// 設定（F-1。「表示」メニューの一番下から）
    @State private var showsSettings = false
    @State private var isScrubbing = false
    @State private var path: [DetailRoute] = []
    // 登録の入口（F1-6）
    @State private var methodRequest: MethodRequest?
    @State private var chosen: (start: RegistrationStart, destination: Shelf)?
    @State private var flow: CaptureViewModel?
    // 並べ替え・棚間移動・削除・一括整列（T7）
    @State private var editing = ShelfEditing()

    var body: some View {
        let all = browseShelves
        let current = all.first { $0.id == currentID } ?? all.first
        NavigationStack(path: $path) {
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 0) {
                    if books.isEmpty || current == nil {
                        emptyLibrary
                    } else if let current {
                        header(current, all: all)
                        content(current, all: all)
                    }
                    hint
                    bottomBar
                }
                if let toast = editing.toast {
                    VStack {
                        Spacer()
                        UndoToast(toast: toast) { undo(toast) }
                            .padding(.bottom, 113)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task(id: toast.id) {
                        do {
                            try await Task.sleep(for: .seconds(5))
                        } catch {
                            return
                        }
                        if editing.toast?.id == toast.id {
                            editing.toast = nil
                        }
                    }
                }
                if let menu = editing.gridMenu, let current {
                    gridMenu(menu, in: current)
                }
                if let book = editing.deleting {
                    DeleteBookDialog(
                        title: book.title,
                        onCancel: { editing.deleting = nil },
                        onDelete: { delete(book) })
                }
                if showsMenu {
                    DisplayMenu(
                        mode: mode,
                        sortKey: current.flatMap {
                            $0.isWishlist ? nil : editing.sortKey(for: $0.shelf, books: $0.books)
                        },
                        onSelectMode: { newMode in
                            editing.clearSelection()
                            mode = newMode
                            showsMenu = false
                        },
                        onSelectSort: { key in
                            if let current {
                                editing.clearSelection()
                                withAnimation(.easeOut(duration: 0.3)) {
                                    editing.sort(current.shelf, by: key, books: current.books, store: environment.store)
                                }
                            }
                            showsMenu = false
                        },
                        onOpenSettings: openSettings,
                        onClose: { showsMenu = false }
                    )
                    .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView(store: environment.store)
            }
            .navigationDestination(for: DetailRoute.self) { route in
                if let book = books.first(where: { $0.id == route.bookID }) {
                    BookDetailView(
                        book: book, backTitle: route.backTitle, environment: environment,
                        onReveal: { reveal($0) })
                } else {
                    Text("この本は見つかりませんでした")
                        .font(BookshelfStyle.sans(15))
                        .foregroundStyle(BookshelfStyle.sub)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsMenu)
        // ジャンル管理で今の棚が削除されたら、中の本が移った未分類を見せる（無ければ先頭の棚）
        .onChange(of: shelves.map(\.persistentModelID)) { _, ids in
            guard let currentID, !ids.contains(currentID) else { return }
            let unsorted = shelves.first { $0.kind == .unsorted }?.persistentModelID
            self.currentID = browseShelves.contains { $0.id == unsorted } ? unsorted : nil
        }
        .animation(.easeOut(duration: 0.2), value: editing.toast?.id)
        .animation(.easeOut(duration: 0.15), value: editing.gridMenu)
        .animation(.easeOut(duration: 0.15), value: editing.deleting?.id)
        .sheet(item: $editing.moving) { book in
            MoveShelfSheet(
                book: book,
                shelves: shelves.filter { $0.kind != .wishlist },
                counts: ownedCounts,
                onMove: { shelf in move(book, to: shelf, in: all) },
                onCancel: { editing.moving = nil })
        }
        .sheet(isPresented: $showsPicker) {
            ShelfPickerSheet(
                entries: all.map { ShelfPickerEntry(shelf: $0.shelf, count: $0.books.count) },
                currentID: current?.id,
                onSelect: { shelf in
                    showsPicker = false
                    select(shelf.persistentModelID, in: all)
                })
        }
        .sheet(item: $methodRequest, onDismiss: beginChosenFlow) { request in
            MethodSheetHost(
                shelves: shelves.filter { $0.kind != .wishlist }, initial: request.destination,
                onSelect: { start, destination in
                    chosen = (start, destination)
                    methodRequest = nil
                },
                onCancel: { methodRequest = nil })
        }
        .fullScreenCover(item: $flow) { model in
            RegistrationFlowView(model: model) { registered in
                let destination = model.destination
                flow = nil
                if registered > 0 {
                    showRegistered(in: destination)
                }
            }
        }
    }

    // MARK: - 棚の一覧（§10.6）

    /// 閲覧画面に出す棚: 購入済みの本が1冊以上あるジャンル・未分類と、買いたい本（0冊でも出す）。
    /// 「買いたい」の本しかないジャンルは出さない
    private var browseShelves: [BrowseShelf] {
        var owned: [PersistentIdentifier: [Book]] = [:]
        var wanted: [Book] = []
        for book in books {
            if book.ownership == .wanted {
                wanted.append(book)
            } else if let shelf = book.shelf {
                owned[shelf.persistentModelID, default: []].append(book)
            }
        }
        wanted.sort { $0.addedAt < $1.addedAt }
        return shelves.compactMap { shelf in
            if shelf.kind == .wishlist {
                return BrowseShelf(shelf: shelf, books: wanted)
            }
            guard let list = owned[shelf.persistentModelID], !list.isEmpty else { return nil }
            return BrowseShelf(shelf: shelf, books: list)
        }
    }

    /// 棚ごとの購入済みの本の冊数（移動先を選ぶリスト D-2）
    private var ownedCounts: [PersistentIdentifier: Int] {
        var counts: [PersistentIdentifier: Int] = [:]
        for book in books where book.ownership == .owned {
            if let shelf = book.shelf {
                counts[shelf.persistentModelID, default: 0] += 1
            }
        }
        return counts
    }

    private func position(of shelf: BrowseShelf) -> Int {
        let last = max(shelf.books.count - (shelf.showsSlot ? 0 : 1), 0)
        return min(max(positions[shelf.id] ?? 0, 0), last)
    }

    /// 棚をかえる（縦スワイプ・グリッドの左右スワイプ）。開いた棚は「直前に使った棚」として記録する（N-031・F1-5）
    private func move(by delta: Int, from current: BrowseShelf, in all: [BrowseShelf]) {
        guard let index = all.firstIndex(where: { $0.id == current.id }) else { return }
        let next = index + delta
        guard all.indices.contains(next) else { return }
        editing.clearSelection()
        shelfEdge = delta > 0 ? .bottom : .top
        withAnimation(.easeOut(duration: 0.3)) {
            currentID = all[next].id
        }
        environment.recent.record(all[next].shelf)
    }

    /// 棚一覧から選ぶ
    private func select(_ id: PersistentIdentifier, in all: [BrowseShelf]) {
        guard let target = all.first(where: { $0.id == id }) else { return }
        editing.clearSelection()
        let from = all.firstIndex { $0.id == currentID } ?? 0
        let to = all.firstIndex { $0.id == id } ?? 0
        shelfEdge = to >= from ? .bottom : .top
        withAnimation(.easeOut(duration: 0.3)) {
            currentID = id
        }
        environment.recent.record(target.shelf)
    }

    /// 詳細で「購入した」・編集・取り消しをしたあと、戻ったときにその本が並ぶ棚とその位置を見せる（T9）。
    /// 購入済みはジャンルの棚、「買いたい」は買いたい本の棚
    private func reveal(_ book: Book) {
        guard !book.isDeleted, book.modelContext != nil else { return }
        let target =
            book.ownership == .wanted ? shelves.first { $0.kind == .wishlist } : book.shelf
        guard let target else { return }
        let id = target.persistentModelID
        let list: [Book]
        if book.ownership == .wanted {
            list = books.filter { $0.ownership == .wanted }.sorted { $0.addedAt < $1.addedAt }
        } else {
            list = environment.store.books(in: target)
        }
        editing.clearSelection()
        editing.toast = nil
        positions[id] = max(list.firstIndex { $0.id == book.id } ?? 0, 0)
        currentID = id
    }

    /// 登録を終えたら、登録先の棚の末尾（新しく並んだ本）を見せる（C-4）
    private func showRegistered(in destination: Shelf) {
        let id = destination.persistentModelID
        guard let shelf = browseShelves.first(where: { $0.id == id }) else { return }
        positions[id] = max(shelf.books.count - 1, 0)
        shelfEdge = .bottom
        currentID = id
    }

    // MARK: - 上（棚の名前・冊数・共有マーク）

    private func header(_ current: BrowseShelf, all: [BrowseShelf]) -> some View {
        ZStack(alignment: .top) {
            Button {
                showsPicker = true
            } label: {
                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 7) {
                        Text(current.shelf.name)
                            .font(BookshelfStyle.serif(22, relativeTo: .title2))
                            .tracking(0.5)
                            .foregroundStyle(BookshelfStyle.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BookshelfStyle.sub)
                    }
                    .frame(minHeight: 32)
                    Text("\(current.books.count)冊")
                        .font(BookshelfStyle.sans(12))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.sub)
                        .accessibilityIdentifier("shelf.count")
                }
                .padding(.horizontal, 70)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current.shelf.name)
            .accessibilityValue("\(current.books.count)冊")
            .accessibilityHint("棚の一覧を開きます")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("shelf.title")
            .accessibilityAction(named: "次の棚") { move(by: 1, from: current, in: all) }
            .accessibilityAction(named: "前の棚") { move(by: -1, from: current, in: all) }
            HStack {
                Spacer()
                // 共有（F8）は T11。買いたい本の棚では出さない（共有画像に「買いたい」の本を含めないため）
                if !current.isWishlist {
                    Button {
                    } label: {
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
            .padding(.trailing, 22)
            .offset(y: -4)
        }
        .padding(.top, 44)
    }

    // MARK: - 中（棚表示・グリッド表示）

    @ViewBuilder
    private func content(_ current: BrowseShelf, all: [BrowseShelf]) -> some View {
        ZStack {
            Group {
                if current.isWishlist && current.books.isEmpty {
                    wishlistEmpty
                } else if mode == .grid {
                    grid(current, all: all)
                } else {
                    shelfView(current, all: all)
                }
            }
            .id(current.id)
            .transition(
                mode == .grid
                    ? .asymmetric(
                        insertion: .move(edge: shelfEdge == .bottom ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: shelfEdge == .bottom ? .leading : .trailing).combined(with: .opacity))
                    : .asymmetric(
                        insertion: .move(edge: shelfEdge).combined(with: .opacity),
                        removal: .move(edge: shelfEdge == .bottom ? .top : .bottom).combined(with: .opacity)))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if mode == .shelf || (current.isWishlist && current.books.isEmpty) {
                ShelfIndicator(count: all.count, index: all.firstIndex { $0.id == current.id } ?? 0)
                    .padding(.trailing, 26)
                    .padding(.top, indicatorTop)
            }
        }
    }

    /// 棚インジケーター（Figma 45:21007）の上端。書影の下・本の情報の横（y≈548）
    private var indicatorTop: CGFloat { 388 }

    private func shelfView(_ base: BrowseShelf, all: [BrowseShelf]) -> some View {
        // 長押しで選んだ本を横にドラッグしている間は、行き先の位置に並べて見せる（H-1）
        let current = base.with(books: editing.previewBooks(base.books, shelfID: base.id))
        let selection = editing.selection.flatMap { $0.shelfID == base.id ? $0 : nil }
        let index = selection?.to ?? position(of: current)
        return VStack(spacing: 0) {
            ZStack {
                // D8: 棚板は置かない。中央の表紙の下に、床に落ちる柔らかい影だけを置く（Figma 00・B-1・M-1 の見え方）
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(0.07), Color.black.opacity(0)], center: .center,
                            startRadius: 0, endRadius: 150)
                    )
                    .frame(width: 300, height: 26)
                    .offset(y: 140)
                ShelfCollectionView(
                    items: current.items,
                    showsSlot: current.showsSlot,
                    centerIndex: index,
                    store: environment.store.images,
                    onCenterChange: { positions[current.id] = $0 },
                    onTapBook: { openDetail(current.books[$0], from: current) },
                    onTapSlot: { open(from: current.shelf) },
                    onVerticalSwipe: { move(by: $0, from: current, in: all) },
                    selectedIndex: selection?.to,
                    onReorderEvent: { handleReorder($0, in: base) },
                    onTapWhileSelected: { editing.clearSelection() })
                if let selection {
                    SelectionArrows(
                        selection: selection, allowsReorder: base.allowsReorder, count: base.books.count,
                        onStep: { step($0, in: base) },
                        onMove: { request(.move(bookID: selection.bookID), in: base) },
                        onDelete: { request(.delete(bookID: selection.bookID), in: base) }
                    )
                    .offset(y: -PinLayout.liftHeight)
                }
            }
            .frame(height: 324)
            .padding(.top, 64)
            .opacity(isScrubbing ? 0.35 : 1)
            .animation(.easeOut(duration: 0.15), value: selection)
            bookInfo(current, index: index, selection: selection)
                .opacity(isScrubbing ? 0 : 1)
            if selection == nil, current.books.count >= Scrubber.threshold, index < current.books.count {
                Scrubber(
                    items: current.items,
                    index: index,
                    store: environment.store.images,
                    isScrubbing: $isScrubbing,
                    onCommit: { positions[current.id] = $0 }
                )
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
    }

    /// 本の情報（題名 → 購入日 → 位置。買いたい本はジャンルと「買いたい」のタグ。空き枠は追加の案内）
    @ViewBuilder
    private func bookInfo(_ current: BrowseShelf, index: Int, selection: ShelfEditing.Selection?) -> some View {
        VStack(spacing: 6) {
            if let selection, index < current.books.count {
                // 長押しで選んだ本（D-1）・横にドラッグしている途中（H-1）
                Text(current.books[index].title)
                    .font(BookshelfStyle.serif(20, relativeTo: .title3))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .accessibilityIdentifier("shelf.bookTitle")
                SelectionInfo(selection: selection, allowsReorder: current.allowsReorder, count: current.books.count)
                    .padding(.top, 6)
            } else if index < current.books.count {
                let book = current.books[index]
                Text(book.title)
                    .font(BookshelfStyle.serif(20, relativeTo: .title3))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .accessibilityIdentifier("shelf.bookTitle")
                if current.isWishlist {
                    HStack(spacing: 10) {
                        Text(book.shelf?.name ?? "未分類")
                            .font(BookshelfStyle.serif(12))
                            .tracking(0.5)
                            .foregroundStyle(BookshelfStyle.sub)
                        Text("買いたい")
                            .font(BookshelfStyle.sans(10))
                            .foregroundStyle(BookshelfStyle.sub)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .overlay(Capsule().stroke(Color(red: 0xD0 / 255, green: 0xD0 / 255, blue: 0xD0 / 255)))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("shelf.bookMeta")
                } else if let date = book.purchaseDate {
                    Text("\(BookDates.format(date)) 購入")
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.sub)
                        .accessibilityIdentifier("shelf.bookMeta")
                }
                Text("\(index + 1) / \(current.books.count)")
                    .font(BookshelfStyle.sans(11))
                    .tracking(1)
                    .foregroundStyle(BookshelfStyle.faint)
                    .padding(.top, 2)
                    .accessibilityIdentifier("shelf.position")
            } else {
                Text("この棚に本を追加")
                    .font(BookshelfStyle.sans(18, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityIdentifier("shelf.bookTitle")
                Text("タップして撮影・登録先  \(current.shelf.name)")
                    .font(BookshelfStyle.sans(12))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
                Text("棚の末尾")
                    .font(BookshelfStyle.sans(11))
                    .tracking(1)
                    .foregroundStyle(BookshelfStyle.faint)
                    .padding(.top, 2)
                    .accessibilityIdentifier("shelf.position")
            }
        }
        .frame(maxWidth: .infinity)
        // 選択中は Figma D-1 のとおり、下の矢印の分だけ題名を下げる
        .padding(.top, selection == nil ? 0 : 17)
        .contentShape(Rectangle())
        .onTapGesture {
            if selection != nil { editing.clearSelection() }
        }
    }

    private func grid(_ current: BrowseShelf, all: [BrowseShelf]) -> some View {
        ShelfGridView(
            items: current.items,
            store: environment.store.images,
            onTapBook: { openDetail(current.books[$0], from: current) },
            onHorizontalSwipe: { move(by: $0, from: current, in: all) },
            allowsReorder: current.allowsReorder,
            onLongPress: { index, frame in
                guard current.books.indices.contains(index) else { return }
                editing.gridMenu = ShelfEditing.GridMenu(bookID: current.books[index].id, index: index, frame: frame)
            },
            onDragStart: { editing.gridMenu = nil },
            onMove: { from, to in
                guard current.books.indices.contains(from) else { return }
                editing.commitReorder(current.books[from], to: to, store: environment.store)
            }
        )
        // Figma I-1: 1行目の表紙の上端 y=176（冊数のすぐ下）
        .padding(.top, 12)
    }

    /// 買いたい本が0冊のとき（M-2）
    private var wishlistEmpty: some View {
        VStack(spacing: 0) {
            EmptyCoverBox(kind: .wishlist)
                .padding(.top, 100)
                .accessibilityHidden(true)
            Text("買いたい本はまだありません")
                .font(BookshelfStyle.sans(18, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 30)
                .accessibilityIdentifier("wishlist.emptyTitle")
            Text("登録するときに「購入済み」のチェックを外すと、\nここに並びます。")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(BookshelfStyle.sub)
                .padding(.top, 12)
                .accessibilityIdentifier("wishlist.emptyMessage")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let all = browseShelves
                guard let current = all.first(where: { $0.id == currentID }) ?? all.first else { return }
                if abs(value.translation.height) > abs(value.translation.width) {
                    move(by: value.translation.height < 0 ? 1 : -1, from: current, in: all)
                } else if mode == .grid {
                    // グリッド表示では左右スワイプで棚をかえる（N-052。ヒント「←→ 棚をかえる」のとおり）
                    move(by: value.translation.width < 0 ? 1 : -1, from: current, in: all)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wishlist.empty")
    }

    /// 本が1冊もないとき（§10.6。通常は初回チュートリアル T14 で1冊登録するため出ない）。＋から登録へ誘導する
    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                open(from: initialShelf())
            } label: {
                EmptyCoverBox(kind: .addBook)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("本を追加")
            .accessibilityIdentifier("library.emptyAdd")
            Text("まだ本がありません")
                .font(BookshelfStyle.sans(18, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 30)
            Text("表紙を撮ると、ここに並びます。")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library.empty")
    }

    // MARK: - 下（操作のヒント・下部バー）

    private var hint: some View {
        Text(mode == .grid ? "↑↓ スクロール　←→ 棚をかえる　長押しでメニュー" : "←→ 本をめくる　↑↓ 棚をかえる")
            .font(BookshelfStyle.sans(10.5))
            .foregroundStyle(BookshelfStyle.faint)
            .padding(.bottom, 20)
            .accessibilityHidden(true)
            .opacity(books.isEmpty ? 0 : 1)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showsMenu = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(BookshelfStyle.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("表示")
            .accessibilityIdentifier("browse.display")
            // 検索（F7）は T10。今は形だけ
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(BookshelfStyle.sub)
                Text("題名・よみで検索")
                    .font(BookshelfStyle.sans(15))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(BookshelfStyle.fill))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("browse.search")
            Button {
                // 入口 A: 下部バーの＋（F1-6 A。初期の棚は F1-5）
                open(from: initialShelf())
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(BookshelfStyle.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("本を登録")
            .accessibilityIdentifier("browse.add")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 2)
    }

    // MARK: - 並べ替え・棚間移動・削除（T7。F5・F6-4）

    /// 棚表示の長押し・ドラッグの知らせを受ける
    private func handleReorder(_ event: ShelfReorderHandler.Event, in shelf: BrowseShelf) {
        // 位置は保存済みの並び（プレビュー前）で数える
        let command = withAnimation(.easeOut(duration: 0.2)) {
            editing.handle(event, books: shelf.books, shelfID: shelf.id, allowsReorder: shelf.allowsReorder)
        }
        if let command {
            request(command, in: shelf)
        }
    }

    /// 長押しの操作の結果（並べ替えの確定・移動先のシート・削除の確認）
    private func request(_ command: ShelfEditing.Command, in shelf: BrowseShelf) {
        switch command {
        case .reorder(let bookID, let to):
            guard let book = shelf.books.first(where: { $0.id == bookID }) else { return }
            editing.commitReorder(book, to: to, store: environment.store)
            positions[shelf.id] = to
        case .move(let bookID):
            editing.moving = shelf.books.first { $0.id == bookID }
        case .delete(let bookID):
            editing.deleting = shelf.books.first { $0.id == bookID }
        }
    }

    /// 矢印のボタン（VoiceOver を含む）で1冊ずつ並べ替える
    private func step(_ delta: Int, in shelf: BrowseShelf) {
        guard var selection = editing.selection else { return }
        let to = min(max(selection.from + delta, 0), shelf.books.count - 1)
        guard to != selection.from, let book = shelf.books.first(where: { $0.id == selection.bookID }) else { return }
        selection.from = to
        selection.to = to
        editing.selection = selection
        editing.commitReorder(book, to: to, store: environment.store)
        positions[shelf.id] = to
    }

    /// 別の棚へ移す（D-2 →D-3）。移動先の棚の末尾を見せ、取り消しのトーストを出す
    private func move(_ book: Book, to shelf: Shelf, in all: [BrowseShelf]) {
        let origin = all.first { $0.books.contains { $0.id == book.id } }
        let fromIndex = origin?.books.firstIndex { $0.id == book.id }
        editing.moving = nil
        editing.clearSelection()
        editing.gridMenu = nil
        guard editing.commitMove(book, to: shelf, fromIndex: fromIndex, store: environment.store) else { return }
        // 「買いたい」の本は買いたい本の棚に出たまま（ジャンルだけが変わる）
        guard book.ownership == .owned else { return }
        let id = shelf.persistentModelID
        positions[id] = max(environment.store.books(in: shelf).firstIndex { $0.id == book.id } ?? 0, 0)
        shelfEdge = .bottom
        withAnimation(.easeOut(duration: 0.3)) {
            currentID = id
        }
        environment.recent.record(shelf)
    }

    /// 移動を取り消す（元の棚・元の位置へ戻す）
    private func undo(_ toast: ShelfEditing.Toast) {
        guard let shelf = editing.undo(toast, store: environment.store), toast.undo?.book.ownership == .owned else {
            return
        }
        let id = shelf.persistentModelID
        if let index = toast.fromIndex {
            positions[id] = index
        }
        shelfEdge = .top
        withAnimation(.easeOut(duration: 0.3)) {
            currentID = id
        }
    }

    /// 削除する（確認ダイアログの「削除」）
    private func delete(_ book: Book) {
        editing.deleting = nil
        editing.clearSelection()
        editing.gridMenu = nil
        withAnimation(.easeOut(duration: 0.25)) {
            editing.commitDelete(book, store: environment.store)
        }
    }

    /// 設定を開く（F4-0）。選択中・取り消しのトーストは閉じる（設定で棚が消えると、取り消しの戻り先が無くなるため）
    private func openSettings() {
        showsMenu = false
        editing.clearSelection()
        editing.gridMenu = nil
        editing.toast = nil
        showsSettings = true
    }

    /// グリッドの長押しメニュー（I-2）
    private func gridMenu(_ menu: ShelfEditing.GridMenu, in current: BrowseShelf) -> some View {
        let book = current.books.first { $0.id == menu.bookID }
        return GridBookMenu(
            menu: menu,
            allowsReorder: current.allowsReorder,
            onDetail: {
                editing.gridMenu = nil
                if let book { openDetail(book, from: current) }
            },
            onMove: {
                editing.gridMenu = nil
                editing.moving = book
            },
            onDelete: {
                editing.gridMenu = nil
                editing.deleting = book
            },
            onClose: { editing.gridMenu = nil })
    }

    // MARK: - 詳細・登録の入口

    private func openDetail(_ book: Book, from shelf: BrowseShelf) {
        path.append(DetailRoute(bookID: book.id, backTitle: shelf.shelf.name))
    }

    private func initialShelf() -> Shelf? {
        do {
            return try environment.recent.initialShelf(in: environment.store)
        } catch {
            return shelves.first { $0.kind == .unsorted }
        }
    }

    private func open(from shelf: Shelf?) {
        guard let shelf else { return }
        chosen = nil
        methodRequest = MethodRequest(destination: shelf)
    }

    /// シートが閉じきってから撮影登録フローを出す
    private func beginChosenFlow() {
        guard let (start, destination) = chosen else { return }
        chosen = nil
        let model = CaptureViewModel(
            store: environment.store, camera: environment.makeCamera(), destination: destination,
            recent: environment.recent, screen: start == .camera ? .camera : .pending)
        model.opensLibraryOnAppear = start == .library
        flow = model
    }
}

// MARK: - 棚インジケーター

/// 画面右の縦に5つの点（中央が今の棚で大きく黒、外側ほど小さく薄い）。表示は5つで、棚の数だけ動く（design-brief §3）
struct ShelfIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(-2...2, id: \.self) { offset in
                let exists = (0..<count).contains(index + offset)
                Circle()
                    .fill(offset == 0 ? BookshelfStyle.ink : BookshelfStyle.faint)
                    .frame(width: dotSize(offset), height: dotSize(offset))
                    .opacity(exists ? (abs(offset) == 2 ? 0.6 : 1) : 0)
                    .frame(width: 12, height: 14)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("棚の位置")
        .accessibilityValue("\(index + 1) / \(count)")
        .accessibilityIdentifier("shelf.indicator")
    }

    private func dotSize(_ offset: Int) -> CGFloat {
        switch abs(offset) {
        case 0: 7
        case 1: 5
        default: 3.5
        }
    }
}

// MARK: - スクラバー（P-1・P-2。F6-9）

/// 100冊以上の棚で、位置の下に出す細い線とつまみ。なぞると上に行き先の表紙・題名・位置を出し、指を離すとその本へ移る
struct Scrubber: View {
    static let threshold = 100

    let items: [ShelfBookItem]
    let index: Int
    let store: ImageStore
    @Binding var isScrubbing: Bool
    let onCommit: (Int) -> Void
    @State private var target: Int?

    var body: some View {
        GeometryReader { geometry in
            let width = isScrubbing ? geometry.size.width - 68 : 140
            let left = (geometry.size.width - width) / 2
            let shown = target ?? index
            let fraction = items.count > 1 ? CGFloat(shown) / CGFloat(items.count - 1) : 0
            let thumbX = left + width * fraction
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(BookshelfStyle.faint)
                    .frame(width: width, height: isScrubbing ? 4 : 2)
                    .offset(x: left, y: 21 - (isScrubbing ? 2 : 1))
                Capsule()
                    .fill(BookshelfStyle.ink)
                    .frame(width: max(width * fraction, 0), height: isScrubbing ? 4 : 2)
                    .offset(x: left, y: 21 - (isScrubbing ? 2 : 1))
                Circle()
                    .fill(BookshelfStyle.ink)
                    .frame(width: isScrubbing ? 22 : 10, height: isScrubbing ? 22 : 10)
                    .offset(x: thumbX - (isScrubbing ? 11 : 5), y: 21 - (isScrubbing ? 11 : 5))
                if isScrubbing, items.indices.contains(shown) {
                    ScrubPreview(item: items[shown], position: shown + 1, count: items.count, store: store)
                        .offset(x: min(max(thumbX - 88, 16), geometry.size.width - 192), y: -186)
                    Text("指を離すと、この本へ移動します")
                        .font(BookshelfStyle.sans(11))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.sub)
                        .frame(width: geometry.size.width)
                        .offset(y: 48)
                }
            }
            .frame(width: geometry.size.width, height: 42, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            withAnimation(.easeOut(duration: 0.15)) { isScrubbing = true }
                        }
                        let full = geometry.size.width - 68
                        let ratio = min(max((value.location.x - 34) / full, 0), 1)
                        target = Int((ratio * CGFloat(items.count - 1)).rounded())
                    }
                    .onEnded { _ in
                        if let target {
                            onCommit(target)
                        }
                        target = nil
                        withAnimation(.easeOut(duration: 0.15)) { isScrubbing = false }
                    }
            )
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel("スクラバー")
        .accessibilityValue("\(index + 1) / \(items.count)")
        .accessibilityAdjustableAction { direction in
            let step = max(items.count / 20, 1)
            switch direction {
            case .increment: onCommit(min(index + step, items.count - 1))
            case .decrement: onCommit(max(index - step, 0))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("shelf.scrubber")
    }
}

/// スクラバーをなぞっている間の、行き先のカード（P-2）
struct ScrubPreview: View {
    let item: ShelfBookItem
    let position: Int
    let count: Int
    let store: ImageStore
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(BookshelfStyle.fill).aspectRatio(0.7, contentMode: .fit)
                }
            }
            .frame(height: 92)
            Text(item.title)
                .font(BookshelfStyle.serif(15))
                .foregroundStyle(BookshelfStyle.ink)
                .lineLimit(1)
            Text("\(position) / \(count)")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: 176)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 10)
        .accessibilityIdentifier("shelf.scrubPreview")
        .task(id: item.id) {
            image = CoverImageCache.shared.cachedThumbnail(for: item.id)
            if image == nil {
                image = await CoverImageCache.shared.thumbnail(for: item.id, in: store)
            }
        }
    }
}

// MARK: - 登録の入口（T5 の仮の入口 ContentView から移した）

extension CaptureViewModel: Identifiable {}

/// 登録方法のシートを開く依頼（どの棚から始めたか）
struct MethodRequest: Identifiable {
    let id = UUID()
    let destination: Shelf
}

/// 登録方法のシート（A-2）の入れ物。シートの中で登録先を変えられるよう、状態をここで持つ
struct MethodSheetHost: View {
    let shelves: [Shelf]
    @State private var destination: Shelf
    let onSelect: (RegistrationStart, Shelf) -> Void
    let onCancel: () -> Void

    init(
        shelves: [Shelf], initial: Shelf, onSelect: @escaping (RegistrationStart, Shelf) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.shelves = shelves
        _destination = State(initialValue: initial)
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        RegistrationMethodSheet(
            shelves: shelves, destination: $destination, onSelect: { onSelect($0, destination) }, onCancel: onCancel)
    }
}
