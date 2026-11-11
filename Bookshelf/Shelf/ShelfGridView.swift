import SwiftUI
import UIKit

/// グリッド表示（I-1。横3列）。縦スクロールで一覧を送り、左右スワイプで棚をかえる（F6-6）。
/// 長押しでメニュー（I-2）を出し、そのままドラッグすると並べ替える（T7。F5-1）
struct ShelfGridView: UIViewRepresentable {
    let items: [ShelfBookItem]
    let store: ImageStore
    let onTapBook: (Int) -> Void
    /// 左右スワイプ（+1 = 次の棚・左へ、-1 = 前の棚・右へ）
    let onHorizontalSwipe: (Int) -> Void
    /// ドラッグで並べ替えられるか（買いたい本は登録した順なので並べ替えない）
    var allowsReorder = true
    /// 長押しでメニューを出す（本の番号・セルの画面上の位置）
    var onLongPress: (Int, CGRect) -> Void = { _, _ in }
    /// 長押しのままドラッグを始めた（メニューを閉じる）
    var onDragStart: () -> Void = {}
    /// ドラッグの並べ替えを確定した（元の位置・新しい位置）
    var onMove: (Int, Int) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.showsHorizontalScrollIndicator = false
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.prefetchDataSource = context.coordinator
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseID)
        view.accessibilityIdentifier = "grid"
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
            swipe.direction = direction
            swipe.delegate = context.coordinator
            view.addGestureRecognizer(swipe)
            context.coordinator.swipes.append(swipe)
        }
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        view.addGestureRecognizer(longPress)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let changed = context.coordinator.items != items
        context.coordinator.parent = self
        if changed {
            context.coordinator.items = items
            view.reloadData()
        }
    }

    /// 3列。列の間 12、行の間 14、左右の余白 20（Figma I-1: 1行 186pt = 表紙 146 + 8 + 題名 18 + 14）
    private static func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / 3), heightDimension: .absolute(GridCellContent.height)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .absolute(GridCellContent.height)),
            repeatingSubitem: item, count: 3)
        group.interItemSpacing = .fixed(12)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20)
        return UICollectionViewCompositionalLayout(section: section)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate
    {
        static let reuseID = "GridCell"
        var parent: ShelfGridView
        /// 表示中の並び（ドラッグの並べ替えはまずここを入れ替え、保存後の新しい並びと突き合わせる）
        var items: [ShelfBookItem]
        weak var view: UICollectionView?
        var swipes: [UIGestureRecognizer] = []
        private var pressed: (index: Int, start: CGPoint)?
        private var isMoving = false

        init(_ parent: ShelfGridView) {
            self.parent = parent
            self.items = parent.items
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
            -> UICollectionViewCell
        {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            let item = items[indexPath.item]
            let store = parent.store
            let index = indexPath.item
            cell.contentConfiguration = UIHostingConfiguration {
                GridCellContent(item: item, index: index, store: store) { [weak self] in
                    self?.openMenu(at: index)
                }
                .id(item.id)
            }
            .margins(.all, 0)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let store = parent.store
            for indexPath in indexPaths where indexPath.item < items.count {
                let id = items[indexPath.item].id
                Task { _ = await CoverImageCache.shared.thumbnail(for: id, in: store) }
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            parent.onTapBook(indexPath.item)
        }

        // MARK: 並べ替え（I-2「そのままドラッグで並べ替え」）

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            parent.allowsReorder
        }

        func collectionView(
            _ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath
        ) {
            items = ShelfOrdering.moved(items, from: sourceIndexPath.item, to: destinationIndexPath.item)
            parent.onMove(sourceIndexPath.item, destinationIndexPath.item)
            // 番号・識別子（grid.book.n）を新しい並びに合わせる
            collectionView.reconfigureItems(at: collectionView.indexPathsForVisibleItems)
        }

        /// メニューを出す（長押し・VoiceOver の操作）
        private func openMenu(at index: Int) {
            guard let view, let cell = view.cellForItem(at: IndexPath(item: index, section: 0)) else { return }
            parent.onLongPress(index, cell.convert(cell.bounds, to: nil))
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                guard let indexPath = view.indexPathForItem(at: point) else { return }
                pressed = (indexPath.item, point)
                // 長押しの間は、棚をかえる左右スワイプを止める
                for swipe in swipes {
                    swipe.isEnabled = false
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                openMenu(at: indexPath.item)
            case .changed:
                guard let pressed else { return }
                if !isMoving, parent.allowsReorder, hypot(point.x - pressed.start.x, point.y - pressed.start.y) > 10 {
                    isMoving = view.beginInteractiveMovementForItem(at: IndexPath(item: pressed.index, section: 0))
                    if isMoving {
                        parent.onDragStart()
                    }
                }
                if isMoving {
                    view.updateInteractiveMovementTargetPosition(point)
                }
            case .ended:
                finish(view, commit: true)
            case .cancelled, .failed:
                finish(view, commit: false)
            default:
                break
            }
        }

        private func finish(_ view: UICollectionView, commit: Bool) {
            if isMoving {
                if commit {
                    view.endInteractiveMovement()
                } else {
                    view.cancelInteractiveMovement()
                }
            }
            isMoving = false
            pressed = nil
            for swipe in swipes {
                swipe.isEnabled = true
            }
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            parent.onHorizontalSwipe(gesture.direction == .left ? 1 : -1)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}
