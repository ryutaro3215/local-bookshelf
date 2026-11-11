import SwiftUI
import UIKit

// MARK: - ピン型の並び（design-brief §3「書影の並び」）

/// 中央の表紙を大きく、左右に最大4冊ずつ外側ほど小さく・少し上に・奥に並べる（ボウリングのピン型）。
/// 横スクロールの量 `pageWidth` ごとに1冊めくれる。位置・大きさは、中央からの距離（小数）で表の値を補間する。
/// 暗さと影はセルが倍率から決める（`ShelfCell.apply`）
final class PinLayout: UICollectionViewLayout {
    /// 1冊めくるのに要る横スクロールの量
    static let pageWidth: CGFloat = 92
    /// 中央の表紙の枠（Figma 41:20902: 184×264）
    static let bookSize = CGSize(width: 184, height: 264)
    /// 中央からの距離 0〜4 冊目の、横のずれ・倍率・持ち上げ・暗さ（Figma の書影の位置から読み取った値）
    static let offsets: [CGFloat] = [0, 67.5, 107.5, 138.5, 161]
    static let scales: [CGFloat] = [1, 0.80, 0.66, 0.55, 0.46]
    static let lifts: [CGFloat] = [0, 5.5, 10, 12.5, 14.5]
    /// 中央から何冊目まで見せるか
    static let visibleRange: CGFloat = 4.5
    /// 長押しで選んだ本を浮かせる量（design-brief §6: 上へ 12pt 前後）
    static let liftHeight: CGFloat = 12

    /// 長押しで選んでいる本（浮かせて影を濃くする）
    var liftedIndex: Int?
    /// 浮かせた本の重なりの順（セルはこの値で浮かせた本と分かる）
    static let liftedZIndex = 2000

    private var count: Int {
        collectionView?.numberOfItems(inSection: 0) ?? 0
    }

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        let width = CGFloat(max(count - 1, 0)) * Self.pageWidth + collectionView.bounds.width
        return CGSize(width: width, height: collectionView.bounds.height)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

    /// 今の中央（小数。0 = 1冊目が中央）
    var position: CGFloat {
        (collectionView?.contentOffset.x ?? 0) / Self.pageWidth
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard count > 0 else { return [] }
        let center = position
        let first = max(0, Int((center - Self.visibleRange).rounded(.down)))
        let last = min(count - 1, Int((center + Self.visibleRange).rounded(.up)))
        guard first <= last else { return [] }
        return (first...last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        let lifted = indexPath.item == liftedIndex
        let distance = CGFloat(indexPath.item) - position
        let far = abs(distance)
        let side: CGFloat = distance < 0 ? -1 : 1
        let bounds = collectionView.bounds
        attributes.size = Self.bookSize
        attributes.center = CGPoint(
            x: bounds.minX + bounds.width / 2 + side * Self.interpolate(Self.offsets, far, extra: 20),
            y: bounds.height / 2 - Self.interpolate(Self.lifts, far, extra: 2) - (lifted ? Self.liftHeight : 0))
        let scale = Self.interpolate(Self.scales, far, extra: -0.08)
        attributes.transform = CGAffineTransform(scaleX: scale, y: scale)
        // 手前の本ほど前に重なる
        attributes.zIndex = lifted ? Self.liftedZIndex : 1000 - Int(far * 100)
        attributes.alpha = far <= 4 ? 1 : max(0, 1 - (far - 4) / (Self.visibleRange - 4))
        return attributes
    }

    /// 表の値を距離で補間する（表より外側は1冊ごとに extra ずつ伸ばす）
    static func interpolate(_ table: [CGFloat], _ distance: CGFloat, extra: CGFloat) -> CGFloat {
        let lastIndex = table.count - 1
        if distance >= CGFloat(lastIndex) {
            return table[lastIndex] + (distance - CGFloat(lastIndex)) * extra
        }
        let lower = Int(distance.rounded(.down))
        let t = distance - CGFloat(lower)
        return table[lower] + (table[lower + 1] - table[lower]) * t
    }

    /// 指を離したら、いちばん近い1冊（勢いがあればその先）でぴたりと止める
    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard count > 0 else { return proposedContentOffset }
        let index = min(max((proposedContentOffset.x / Self.pageWidth).rounded(), 0), CGFloat(count - 1))
        return CGPoint(x: index * Self.pageWidth, y: 0)
    }
}

// MARK: - 棚表示（横スワイプで本をめくる・縦スワイプで棚をかえる）

/// 棚表示の本体（UIKit の UICollectionView。plan の stack: 棚の表示は UICollectionView）
struct ShelfCollectionView: UIViewRepresentable {
    let items: [ShelfBookItem]
    /// 末尾に空き枠を出すか（買いたい本の棚には出さない。F1-6 B）
    let showsSlot: Bool
    /// 中央の位置（空き枠のときは items.count）
    let centerIndex: Int
    let store: ImageStore
    let onCenterChange: (Int) -> Void
    let onTapBook: (Int) -> Void
    let onTapSlot: () -> Void
    /// 縦スワイプ（+1 = 次の棚・上へ、-1 = 前の棚・下へ）
    let onVerticalSwipe: (Int) -> Void
    /// 長押しで選んでいる本（nil = 選んでいない）。選択中はスクロール・縦スワイプを止める（T7）
    var selectedIndex: Int?
    /// 長押し・選択中のドラッグ（F5-1b）
    var onReorderEvent: (ShelfReorderHandler.Event) -> Void = { _ in }
    /// 選択中にタップした（選択を解除する）
    var onTapWhileSelected: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ShelfCarouselView {
        let view = ShelfCarouselView(frame: .zero, collectionViewLayout: PinLayout())
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = true
        view.decelerationRate = .fast
        view.clipsToBounds = false
        view.register(ShelfCell.self, forCellWithReuseIdentifier: ShelfCell.reuseID)
        view.register(ShelfSlotCell.self, forCellWithReuseIdentifier: ShelfSlotCell.reuseID)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.prefetchDataSource = context.coordinator
        view.accessibilityIdentifier = "shelf.carousel"
        var swipes: [UIGestureRecognizer] = []
        for direction in [UISwipeGestureRecognizer.Direction.up, .down] {
            let swipe = UISwipeGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
            swipe.direction = direction
            swipe.delegate = context.coordinator
            view.addGestureRecognizer(swipe)
            swipes.append(swipe)
        }
        context.coordinator.reorder.attach(to: view, swipes: swipes)
        context.coordinator.apply(self, to: view, force: true)
        return view
    }

    func updateUIView(_ view: ShelfCarouselView, context: Context) {
        context.coordinator.apply(self, to: view, force: false)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate
    {
        var parent: ShelfCollectionView
        private var reported = 0
        /// 長押しで選んで並べ替え・移動・削除する（T7）
        let reorder = ShelfReorderHandler()
        /// プログラムからのスクロール中は、途中の位置を知らせない
        private var isProgrammaticScroll = false

        init(_ parent: ShelfCollectionView) {
            self.parent = parent
            super.init()
            reorder.onEvent = { [weak self] event in self?.parent.onReorderEvent(event) }
            reorder.canSelect = { [weak self] index in
                guard let self, index < self.parent.items.count else { return false }
                return index == self.reported
            }
        }

        private var itemCount: Int { parent.items.count + (parent.showsSlot ? 1 : 0) }

        func apply(_ next: ShelfCollectionView, to view: ShelfCarouselView, force: Bool) {
            let previous = parent.items
            let previousShowsSlot = parent.showsSlot
            var changed = force || next.items != parent.items || next.showsSlot != parent.showsSlot
            parent = next
            reorder.isSelecting = next.selectedIndex != nil
            if let layout = view.collectionViewLayout as? PinLayout, layout.liftedIndex != next.selectedIndex {
                layout.liftedIndex = next.selectedIndex
                if !changed {
                    UIView.animate(withDuration: 0.2) { layout.invalidateLayout() }
                }
            }
            // 同じ本の並びが入れ替わっただけ（並べ替えの途中）のときは、本を動かすアニメーションで見せる
            if changed, !force, next.showsSlot == previousShowsSlot, isPermutation(previous, next.items),
                view.window != nil
            {
                changed = false
                movePermutation(from: previous, to: next.items, in: view)
            }
            if changed {
                isProgrammaticScroll = true
                view.reloadData()
                view.collectionViewLayout.invalidateLayout()
                isProgrammaticScroll = false
            }
            let target = min(max(next.centerIndex, 0), max(itemCount - 1, 0))
            if changed || (target != reported && !view.isTracking && !view.isDecelerating) {
                reported = target
                scroll(view, to: target, animated: !changed && view.window != nil)
            }
        }

        private func isPermutation(_ old: [ShelfBookItem], _ new: [ShelfBookItem]) -> Bool {
            old.count == new.count && old != new && Set(old.map(\.id)) == Set(new.map(\.id))
        }

        /// 並びの入れ替えを、セルを動かすアニメーションで反映する
        private func movePermutation(from old: [ShelfBookItem], to new: [ShelfBookItem], in view: ShelfCarouselView) {
            let oldIndex = Dictionary(uniqueKeysWithValues: old.enumerated().map { ($1.id, $0) })
            view.performBatchUpdates {
                for (index, item) in new.enumerated() {
                    if let from = oldIndex[item.id], from != index {
                        view.moveItem(at: IndexPath(item: from, section: 0), to: IndexPath(item: index, section: 0))
                    }
                }
            } completion: { _ in
                // 番号・識別子（shelf.book.n）を新しい並びに合わせる
                let visible = view.indexPathsForVisibleItems.filter { $0.item < self.parent.items.count }
                view.reconfigureItems(at: visible)
            }
        }

        private func scroll(_ view: ShelfCarouselView, to index: Int, animated: Bool) {
            isProgrammaticScroll = true
            view.scroll(to: index, animated: animated)
            if !animated {
                isProgrammaticScroll = false
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            itemCount
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
            -> UICollectionViewCell
        {
            if indexPath.item >= parent.items.count {
                return collectionView.dequeueReusableCell(withReuseIdentifier: ShelfSlotCell.reuseID, for: indexPath)
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShelfCell.reuseID, for: indexPath)
            if let cell = cell as? ShelfCell {
                let index = indexPath.item
                cell.configure(parent.items[index], index: index, count: parent.items.count, store: parent.store)
                // VoiceOver では長押しの代わりに「選択」の操作で選ぶ（N5）
                cell.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(name: "選択して並べ替え・移動・削除") { [weak self] _ in
                        guard let self, index == self.reported else { return false }
                        self.parent.onReorderEvent(.began(index))
                        self.parent.onReorderEvent(.ended(.zero))
                        return true
                    }
                ]
            }
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let store = parent.store
            for indexPath in indexPaths where indexPath.item < parent.items.count {
                let id = parent.items[indexPath.item].id
                Task { _ = await CoverImageCache.shared.thumbnail(for: id, in: store) }
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            if parent.selectedIndex != nil {
                parent.onTapWhileSelected()
                return
            }
            let current = Int((collectionView.contentOffset.x / PinLayout.pageWidth).rounded())
            if indexPath.item != current {
                // 横の本をタップしたら、その本を中央へ
                if let view = collectionView as? ShelfCarouselView {
                    scroll(view, to: indexPath.item, animated: true)
                }
                return
            }
            if indexPath.item >= parent.items.count {
                parent.onTapSlot()
            } else {
                parent.onTapBook(indexPath.item)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isProgrammaticScroll = false
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            isProgrammaticScroll = false
            scrollViewDidScroll(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard itemCount > 0, !isProgrammaticScroll else { return }
            let index = min(max(Int((scrollView.contentOffset.x / PinLayout.pageWidth).rounded()), 0), itemCount - 1)
            if index != reported {
                reported = index
                parent.onCenterChange(index)
            }
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            parent.onVerticalSwipe(gesture.direction == .up ? 1 : -1)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

/// 棚表示の UICollectionView。大きさが決まる前に頼まれた位置へのスクロールを、配置のあとで行う
final class ShelfCarouselView: UICollectionView {
    private var pendingIndex: Int?

    func scroll(to index: Int, animated: Bool) {
        guard bounds.width > 0 else {
            pendingIndex = index
            return
        }
        layoutIfNeeded()
        setContentOffset(CGPoint(x: CGFloat(index) * PinLayout.pageWidth, y: 0), animated: animated)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let index = pendingIndex, bounds.width > 0 {
            pendingIndex = nil
            contentOffset = CGPoint(x: CGFloat(index) * PinLayout.pageWidth, y: 0)
        }
    }
}
