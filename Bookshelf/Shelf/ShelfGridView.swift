import SwiftUI
import UIKit

/// グリッド表示（I-1。横3列）。縦スクロールで一覧を送り、左右スワイプで棚をかえる（F6-6）。
/// 長押しのメニュー・ドラッグの並べ替え（I-2）は T7 で足す
struct ShelfGridView: UIViewRepresentable {
    let items: [ShelfBookItem]
    let store: ImageStore
    let onTapBook: (Int) -> Void
    /// 左右スワイプ（+1 = 次の棚・左へ、-1 = 前の棚・右へ）
    let onHorizontalSwipe: (Int) -> Void

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
        }
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let changed = context.coordinator.parent.items != items
        context.coordinator.parent = self
        if changed {
            view.reloadData()
        }
    }

    /// 3列。列の間 12、行の間 22、左右の余白 20（Figma I-1）
    private static func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / 3), heightDimension: .estimated(186)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(186)),
            repeatingSubitem: item, count: 3)
        group.interItemSpacing = .fixed(12)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 22
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20)
        return UICollectionViewCompositionalLayout(section: section)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate
    {
        static let reuseID = "GridCell"
        var parent: ShelfGridView

        init(_ parent: ShelfGridView) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
            -> UICollectionViewCell
        {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            let item = parent.items[indexPath.item]
            let store = parent.store
            let index = indexPath.item
            cell.contentConfiguration = UIHostingConfiguration {
                GridCellContent(item: item, index: index, store: store)
            }
            .margins(.all, 0)
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
            parent.onTapBook(indexPath.item)
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
