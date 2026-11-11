import SwiftData
import SwiftUI
import UIKit
import os

// MARK: - 棚表示の長押し（UIKit のジェスチャ）

/// 棚表示（ピン型の並び）で、中央の本を長押しで選び、そのまま（または選んだあとに）指を動かした量を知らせる（F5-1・F5-1b）。
/// 選択中は横スクロールと縦スワイプ（棚をかえる）を止め、指の動きをすべてここで受ける
final class ShelfReorderHandler: NSObject, UIGestureRecognizerDelegate {
    enum Event {
        /// 長押しで本を選んだ（中央の本の番号）
        case began(Int)
        /// 指を動かしている（長押し・ドラッグを始めた点からの移動量）
        case changed(CGSize)
        /// 指を離した
        case ended(CGSize)
    }

    var onEvent: (Event) -> Void = { _ in }
    /// 長押しで選べる本か（中央の本だけ。空き枠は選べない）
    var canSelect: (Int) -> Bool = { _ in false }

    private let longPress = UILongPressGestureRecognizer()
    private let pan = UIPanGestureRecognizer()
    private weak var view: UICollectionView?
    private var swipes: [UIGestureRecognizer] = []
    private var pressStart: CGPoint?

    /// 選択中か（選択中はスクロールと棚をかえるスワイプを止め、ドラッグを受ける）
    var isSelecting = false {
        didSet {
            guard oldValue != isSelecting else { return }
            pan.isEnabled = isSelecting
            view?.isScrollEnabled = !isSelecting
            for swipe in swipes {
                swipe.isEnabled = !isSelecting
            }
        }
    }

    func attach(to view: UICollectionView, swipes: [UIGestureRecognizer]) {
        self.view = view
        self.swipes = swipes
        longPress.minimumPressDuration = 0.4
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        longPress.delegate = self
        view.addGestureRecognizer(longPress)
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let view else { return }
        // 指の動きは画面の座標で測る（並べ替えのプレビューで横スクロールの位置が変わっても、移動量がずれないように）
        let point = gesture.location(in: nil)
        switch gesture.state {
        case .began:
            guard let indexPath = view.indexPathForItem(at: gesture.location(in: view)), canSelect(indexPath.item)
            else {
                pressStart = nil
                return
            }
            pressStart = point
            // 選んだ瞬間に、始まりかけのスクロール・縦スワイプを止める
            for swipe in swipes {
                swipe.isEnabled = false
            }
            view.isScrollEnabled = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onEvent(.began(indexPath.item))
        case .changed:
            guard let start = pressStart else { return }
            onEvent(.changed(CGSize(width: point.x - start.x, height: point.y - start.y)))
        case .ended, .cancelled, .failed:
            guard let start = pressStart else { return }
            pressStart = nil
            onEvent(.ended(CGSize(width: point.x - start.x, height: point.y - start.y)))
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // 長押しが続いている間は、長押しの側で指の動きを知らせる（二重に知らせない）
        guard let view, pressStart == nil else { return }
        let translation = gesture.translation(in: view.window)
        let size = CGSize(width: translation.x, height: translation.y)
        switch gesture.state {
        case .changed:
            onEvent(.changed(size))
        case .ended, .cancelled, .failed:
            onEvent(.ended(size))
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // 長押しはスクロールと同時に見張る（指を止めて待つと長押しになる）
        gestureRecognizer === longPress
    }
}

// MARK: - 閲覧画面の編集の状態（選択・移動・削除・整列）

/// 閲覧画面での本の並べ替え・棚間移動・削除・一括整列の状態と操作（F5・F6-4）
@MainActor
@Observable
final class ShelfEditing {
    /// 長押しで選んだ本（D-1・H-1）
    struct Selection: Equatable {
        let bookID: UUID
        let shelfID: PersistentIdentifier
        /// 選んだときの位置
        var from: Int
        /// 横にドラッグしている間の、行き先の位置
        var to: Int
        /// ドラッグの向き（決まるまでは nil）
        var axis: Axis?
        /// 縦にドラッグしている量（上 = 負）
        var lift: CGFloat = 0
    }

    /// 移動の取り消しのトースト（D-3）
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let undo: ShelfMoveRecord?
        let fromIndex: Int?
    }

    /// グリッドの長押しメニュー（I-2）
    struct GridMenu: Equatable {
        let bookID: UUID
        let index: Int
        /// 長押しした本のセルの位置（画面の座標）
        let frame: CGRect
    }

    /// 横に1冊ずつ入れ替える指の移動量
    static let stepWidth: CGFloat = 60
    /// 上下に指を動かして、移動・削除にする量
    static let verticalThreshold: CGFloat = 60
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "ShelfEditing")

    var selection: Selection?
    /// 「移動先の棚を選ぶ」シートを出す本（D-2）
    var moving: Book?
    /// 削除の確認を出す本（H-2）
    var deleting: Book?
    var toast: Toast?
    var gridMenu: GridMenu?
    /// 棚ごとに最後に選んだ並べ順（今の並びがその順のときだけチェックを付ける）
    var sortChoices: [PersistentIdentifier: ShelfSortKey] = [:]
    /// 整列する前の手動の並び（「手動」を選ぶとこの並びに戻す。アプリを閉じるまで）
    var manualSnapshots: [PersistentIdentifier: [UUID]] = [:]

    // MARK: 棚表示の長押し・ドラッグ

    /// 長押しのジェスチャの知らせを受ける。`allowsReorder` が false（買いたい本）のときは横の並べ替えをしない
    func handle(_ event: ShelfReorderHandler.Event, books: [Book], shelfID: PersistentIdentifier, allowsReorder: Bool)
        -> Command?
    {
        switch event {
        case .began(let index):
            guard books.indices.contains(index) else { return nil }
            selection = Selection(bookID: books[index].id, shelfID: shelfID, from: index, to: index, axis: nil)
            return nil
        case .changed(let delta):
            guard var current = selection else { return nil }
            if current.axis == nil, max(abs(delta.width), abs(delta.height)) > 12 {
                current.axis = abs(delta.width) > abs(delta.height) ? .horizontal : .vertical
            }
            switch current.axis {
            case .horizontal where allowsReorder:
                let steps = Int((delta.width / Self.stepWidth).rounded(.towardZero))
                let target = min(max(current.from + steps, 0), max(books.count - 1, 0))
                if target != current.to {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                current.to = target
            case .vertical:
                current.lift = max(min(delta.height, 80), -80)
            default:
                break
            }
            selection = current
            return nil
        case .ended(let delta):
            guard var current = selection else { return nil }
            let axis = current.axis
            let from = current.from
            let to = current.to
            current.axis = nil
            current.lift = 0
            current.from = to
            selection = current
            if axis == .horizontal, allowsReorder, from != to {
                return .reorder(bookID: current.bookID, to: to)
            }
            if axis == .vertical {
                if delta.height < -Self.verticalThreshold { return .move(bookID: current.bookID) }
                if delta.height > Self.verticalThreshold { return .delete(bookID: current.bookID) }
            }
            return nil
        }
    }

    /// 長押しの操作の結果、画面がすること
    enum Command: Equatable {
        case reorder(bookID: UUID, to: Int)
        case move(bookID: UUID)
        case delete(bookID: UUID)
    }

    /// 選択中の本を、今の棚の並び（プレビュー）に反映した並び
    func previewBooks(_ books: [Book], shelfID: PersistentIdentifier) -> [Book] {
        guard let selection, selection.shelfID == shelfID, selection.from != selection.to,
            books.indices.contains(selection.from), books[selection.from].id == selection.bookID
        else { return books }
        return ShelfOrdering.moved(books, from: selection.from, to: selection.to)
    }

    func clearSelection() {
        selection = nil
    }

    // MARK: 保存する操作

    /// 横の並べ替えを保存する（手動の並びになる）
    func commitReorder(_ book: Book, to index: Int, store: LibraryStore) {
        do {
            try store.moveBook(book, toIndex: index)
            if let shelf = book.shelf {
                sortChoices[shelf.persistentModelID] = .manual
                manualSnapshots[shelf.persistentModelID] = nil
            }
        } catch {
            Self.logger.error("並べ替えを保存できない: \(error.localizedDescription, privacy: .public)")
            toast = Toast(message: "並べ替えを保存できませんでした", undo: nil, fromIndex: nil)
        }
    }

    /// 別の棚へ移す。成功したら取り消しのトーストを出す
    func commitMove(_ book: Book, to shelf: Shelf, fromIndex: Int?, store: LibraryStore) -> Bool {
        do {
            let record = try store.moveBook(book, to: shelf)
            toast = Toast(message: "\(shelf.name) に移しました", undo: record, fromIndex: fromIndex)
            return true
        } catch {
            Self.logger.error("棚を移せない: \(error.localizedDescription, privacy: .public)")
            toast = Toast(message: "移動できませんでした", undo: nil, fromIndex: nil)
            return false
        }
    }

    /// 取り消す（元の棚・元の位置へ戻す）。戻した棚を返す
    func undo(_ toast: Toast, store: LibraryStore) -> Shelf? {
        guard let record = toast.undo else { return nil }
        self.toast = nil
        do {
            try store.undoMove(record)
            return record.fromShelf
        } catch {
            Self.logger.error("移動を取り消せない: \(error.localizedDescription, privacy: .public)")
            self.toast = Toast(message: "取り消せませんでした", undo: nil, fromIndex: nil)
            return nil
        }
    }

    /// 本を削除する（データを保存できてから表紙の画像を消す。LibraryStore.deleteBook）
    /// 移したばかりの本を消したときは、その本の取り消しのトーストも消す（N-060）
    func commitDelete(_ book: Book, store: LibraryStore) {
        // 削除したあとの本のデータは読まない（削除の前に、同じ本のトーストかを確かめておく）
        let clearsToast = toast?.undo?.bookID == book.id
        do {
            try store.deleteBook(book)
            if clearsToast {
                toast = nil
            }
        } catch {
            Self.logger.error("本を削除できない: \(error.localizedDescription, privacy: .public)")
            toast = Toast(message: "削除できませんでした", undo: nil, fromIndex: nil)
        }
    }

    // MARK: 一括整列（F5-3）

    /// 今の棚にチェックを付ける並べ順（最後に選んだ順でも、その後に並びが変わっていれば手動）
    func sortKey(for shelf: Shelf, books: [Book]) -> ShelfSortKey {
        let key = sortChoices[shelf.persistentModelID] ?? .manual
        return ShelfOrdering.isOrdered(books, by: key) ? key : .manual
    }

    /// 並べ順を選ぶ。手動を選ぶと、整列する前の手動の並びに戻す
    func sort(_ shelf: Shelf, by key: ShelfSortKey, books: [Book], store: LibraryStore) {
        let id = shelf.persistentModelID
        do {
            if key == .manual {
                if let snapshot = manualSnapshots[id] {
                    try store.restoreOrder(in: shelf, ids: snapshot)
                }
                manualSnapshots[id] = nil
            } else {
                if sortKey(for: shelf, books: books) == .manual {
                    manualSnapshots[id] = books.map(\.id)
                }
                try store.sortBooks(in: shelf, by: key)
            }
            sortChoices[id] = key
        } catch {
            Self.logger.error("並べ順を変えられない: \(error.localizedDescription, privacy: .public)")
            toast = Toast(message: "並べ順を変えられませんでした", undo: nil, fromIndex: nil)
        }
    }
}

// MARK: - 選択中の矢印（D-1・H-1）

/// 長押しで選んだ中央の本のまわりに出す、操作の向きの丸いボタン（上: 別の棚へ・下: 削除・左右: 並べ替え）
struct SelectionArrows: View {
    let selection: ShelfEditing.Selection
    let allowsReorder: Bool
    let count: Int
    let onStep: (Int) -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let dragging = selection.axis == .horizontal
        ZStack {
            if !dragging {
                arrow("chevron.up", label: "別の棚へ移動", id: "select.up", action: onMove)
                    .offset(y: -154)
                arrow("chevron.down", label: "削除", id: "select.down", action: onDelete)
                    .offset(y: 154)
            }
            if allowsReorder {
                if selection.to > 0 && (!dragging || selection.to < selection.from) {
                    arrow("chevron.left", label: "前へ並べ替え", id: "select.left") { onStep(-1) }
                        .offset(x: -109)
                }
                if selection.to < count - 1 && (!dragging || selection.to > selection.from) {
                    arrow("chevron.right", label: "後ろへ並べ替え", id: "select.right") { onStep(1) }
                        .offset(x: 109)
                }
            }
        }
        .offset(y: selection.lift * 0.5)
    }

    private func arrow(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BookshelfStyle.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// 選択中の本の情報の下に出す、操作の案内（D-1）と並べ替え中の位置（H-1）
struct SelectionInfo: View {
    let selection: ShelfEditing.Selection
    let allowsReorder: Bool
    let count: Int

    var body: some View {
        VStack(spacing: 10) {
            if selection.axis == .horizontal && allowsReorder {
                Text("\(selection.from + 1) → \(selection.to + 1) / \(count)")
                    .font(BookshelfStyle.sans(13))
                    .tracking(1)
                    .foregroundStyle(BookshelfStyle.sub)
                    .accessibilityIdentifier("select.position")
                Text("左右にスワイプで1冊ずつ入れ替え・指を離して確定")
                    .font(BookshelfStyle.sans(11))
                    .tracking(0.3)
                    .foregroundStyle(BookshelfStyle.faint)
            } else {
                HStack(spacing: 18) {
                    if allowsReorder {
                        guide(["chevron.left", "chevron.right"], "並べ替え")
                    }
                    guide(["chevron.up"], "別の棚へ")
                    guide(["chevron.down"], "削除")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("select.guide")
                Text("選択中（タップで解除）")
                    .font(BookshelfStyle.sans(11))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.faint)
                    .accessibilityIdentifier("select.state")
            }
        }
    }

    private func guide(_ symbols: [String], _ text: String) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(symbols, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            Text(text)
                .font(BookshelfStyle.sans(13))
                .tracking(0.5)
        }
        .foregroundStyle(BookshelfStyle.sub)
    }
}

// MARK: - 移動先の棚を選ぶ（D-2）

/// 移動先の棚を選ぶシート（D-2）。0冊のジャンルも出す。今の棚は薄く「現在の棚」。選んでから「◯◯ へ移動」で確定する
struct MoveShelfSheet: View {
    let book: Book
    let shelves: [Shelf]
    /// 棚ごとの冊数（購入済みの本）
    let counts: [PersistentIdentifier: Int]
    let onMove: (Shelf) -> Void
    let onCancel: () -> Void
    @State private var selected: Shelf?

    var body: some View {
        VStack(spacing: 0) {
            Text("移動先の棚を選ぶ")
                .font(BookshelfStyle.sans(17, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 30)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("move.title")
            Text("\(book.title) ・現在の棚 \(book.shelf?.name ?? "未分類")")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.category.id) { group in
                            Text(group.category.name)
                                .font(BookshelfStyle.sans(11, .medium))
                                .tracking(1)
                                .foregroundStyle(BookshelfStyle.faint)
                                .padding(.horizontal, 26)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.shelves, id: \.persistentModelID) { shelf in
                                row(shelf)
                                    .id(shelf.persistentModelID)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .onAppear {
                    // 今の棚がリストの下の方にあるときだけ、見える位置まで送る（上の方なら Figma D-2 のとおり先頭から見せる）
                    if let current = book.shelf?.persistentModelID,
                        let index = shelves.firstIndex(where: { $0.persistentModelID == current }), index > 5
                    {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
            .padding(.top, 10)
            Button {
                if let selected { onMove(selected) }
            } label: {
                Text(selected.map { "\($0.name) へ移動" } ?? "移動先を選んでください")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(BookshelfStyle.ink.opacity(selected == nil ? 0.3 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(selected == nil)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .accessibilityIdentifier("move.confirm")
            Button(action: onCancel) {
                Text("キャンセル")
                    .font(BookshelfStyle.sans(15))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .accessibilityIdentifier("move.cancel")
        }
        .presentationDetents([.height(582), .large])
        .presentationBackground(Color.white)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private func row(_ shelf: Shelf) -> some View {
        let isCurrent = shelf.persistentModelID == book.shelf?.persistentModelID
        let isSelected = shelf.persistentModelID == selected?.persistentModelID
        let count = counts[shelf.persistentModelID] ?? 0
        return Button {
            selected = shelf
        } label: {
            HStack(spacing: 12) {
                Text(shelf.name)
                    .font(BookshelfStyle.serif(16))
                    .tracking(0.5)
                    .foregroundStyle(isCurrent ? BookshelfStyle.faint : BookshelfStyle.ink)
                    .lineLimit(1)
                Spacer()
                Text(isCurrent ? "現在の棚" : "\(count)冊")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(isCurrent ? BookshelfStyle.faint : BookshelfStyle.sub)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? BookshelfStyle.fill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .padding(.horizontal, 12)
        .accessibilityLabel(shelf.name)
        .accessibilityValue(isCurrent ? "現在の棚" : "\(count)冊")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("move.row.\(shelf.name)")
    }

    /// 区分ごとにまとめる（並びは棚の並び順のまま）
    private var groups: [(category: GenreCategory, shelves: [Shelf])] {
        var result: [(category: GenreCategory, shelves: [Shelf])] = []
        for shelf in shelves {
            let category = InitialGenres.categories.first { $0.id == shelf.categoryID } ?? InitialGenres.myGenres
            if let index = result.firstIndex(where: { $0.category.id == category.id }) {
                result[index].shelves.append(shelf)
            } else {
                result.append((category, [shelf]))
            }
        }
        return result
    }
}

// MARK: - 削除の確認（H-2）

/// 削除の確認ダイアログ（H-2。design-brief §3 のダイアログ: 白・角 18・幅 290、取り消せない側を赤・太字）
struct DeleteBookDialog: View {
    let title: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255).opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("「\(title)」を\n削除しますか？")
                        .font(BookshelfStyle.sans(17, .medium))
                        .tracking(0.5)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BookshelfStyle.ink)
                        .accessibilityIdentifier("delete.title")
                    Text("表紙の写真と本のデータが削除されます。\nこの操作は取り消せません。")
                        .font(BookshelfStyle.sans(13))
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BookshelfStyle.sub)
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 20)
                Rectangle().fill(Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255)).frame(height: 1)
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(BookshelfStyle.sans(16))
                            .foregroundStyle(BookshelfStyle.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("delete.cancel")
                    Rectangle().fill(Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255)).frame(width: 1)
                    Button(action: onDelete) {
                        Text("削除")
                            .font(BookshelfStyle.sans(16, .bold))
                            .foregroundStyle(BookshelfStyle.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("delete.confirm")
                }
                .frame(height: 48)
            }
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("delete.dialog")
        }
        .accessibilityAction(.escape, onCancel)
    }
}

// MARK: - トースト（D-3）

/// 移動のあとに出す通知（INK の地・角 16・高さ 48。右に下線つきの「取り消す」）
struct UndoToast: View {
    let toast: ShelfEditing.Toast
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
            if toast.undo != nil {
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

// MARK: - グリッドの長押しメニュー（I-2）

/// グリッドで長押しした本の上に出すメニュー（詳細を見る・別の棚へ移動・削除）。長押しした本は少し大きく浮かせる
struct GridBookMenu: View {
    let menu: ShelfEditing.GridMenu
    let allowsReorder: Bool
    let onDetail: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    private static let width: CGFloat = 262
    private static let height: CGFloat = 182
    /// 浮かせた表紙の倍率（Figma I-2: 表紙 102×146 → 124×178）
    private static let liftScale: CGFloat = 1.22

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let cell = menu.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            let cover = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: GridCellContent.coverHeight)
            let lifted = cover.insetBy(
                dx: -cover.width * (Self.liftScale - 1) / 2, dy: -cover.height * (Self.liftScale - 1) / 2)
            let x = min(max(cell.midX - Self.width / 2, 16), geometry.size.width - Self.width - 16)
            let above = lifted.minY - 4 - Self.height
            let y = above >= 60 ? above : lifted.maxY + 4
            ZStack(alignment: .topLeading) {
                Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255).opacity(0.30)
                    .onTapGesture(perform: onClose)
                    .accessibilityLabel("閉じる")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("gridMenu.dismiss")
                LiftedCover(bookID: menu.bookID)
                    .frame(width: lifted.width, height: lifted.height, alignment: .bottom)
                    .offset(x: lifted.minX, y: lifted.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                card
                    .offset(x: x, y: y)
            }
        }
        .ignoresSafeArea()
        // 開いている間は VoiceOver で後ろの画面に移れないようにし、「閉じる」ジェスチャでも閉じる（N5）
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    private var card: some View {
        VStack(spacing: 0) {
            row("詳細を見る", symbol: "chevron.right", color: BookshelfStyle.ink, id: "gridMenu.detail", action: onDetail)
            Rectangle().fill(Color(red: 0xE8 / 255, green: 0xE8 / 255, blue: 0xE8 / 255)).frame(height: 1)
            row("別の棚へ移動", symbol: "chevron.up", color: BookshelfStyle.ink, id: "gridMenu.move", action: onMove)
            Rectangle().fill(Color(red: 0xE8 / 255, green: 0xE8 / 255, blue: 0xE8 / 255)).frame(height: 1)
            row("削除", symbol: "trash", color: BookshelfStyle.danger, id: "gridMenu.delete", action: onDelete)
            Rectangle().fill(Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255)).frame(height: 8)
            Text(allowsReorder ? "そのままドラッグで並べ替え" : "買いたい本は登録した順に並びます")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.faint)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .accessibilityHidden(true)
        }
        .frame(width: Self.width)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gridMenu")
    }

    private func row(_ title: String, symbol: String, color: Color, id: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(BookshelfStyle.sans(16))
                    .tracking(0.5)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

/// 浮かせた表紙（サムネイル。縦横比のまま、枠の下にそろえる）
private struct LiftedCover: View {
    let bookID: UUID

    var body: some View {
        if let image = CoverImageCache.shared.cachedThumbnail(for: bookID) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 10)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(BookshelfStyle.fill)
                .aspectRatio(0.7, contentMode: .fit)
        }
    }
}

extension BookshelfStyle {
    /// 取り消せない操作（削除）の赤（design-brief §2-1 DANGER）
    static let danger = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)
}
