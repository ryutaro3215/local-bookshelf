import SwiftUI
import UIKit
import os

/// 棚に並べる本1冊分の表示用の値（UIKit に @Model を渡さないため、値だけを写す）
nonisolated struct ShelfBookItem: Hashable, Sendable {
    let id: UUID
    let title: String
    /// 表紙を撮り直した回数（変わるとセルを描き直す。T9）
    var coverRevision = 0
}

// MARK: - 表紙の読み込み（サムネイル）

/// 表紙のサムネイルをファイルから読み、表示用にデコードしてメモリに置く（棚・グリッドでは原寸を読まない。N1・N2）
@MainActor
@Observable
final class CoverImageCache {
    static let shared = CoverImageCache()

    @ObservationIgnored private let thumbnails = NSCache<NSUUID, UIImage>()
    @ObservationIgnored private var loading: [UUID: Task<UIImage?, Never>] = [:]
    /// 表紙を入れ替えた本ごとの回数（画面はこれを見て描き直す）
    private(set) var revisions: [UUID: Int] = [:]
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Shelf")

    /// 展開後のサムネイルを置いておく量の上限（バイト。N-051: 長辺 400px で1枚約 0.4〜0.5MB → 約 160〜200 冊分）
    static let byteLimit = 80 * 1024 * 1024

    init() {
        thumbnails.countLimit = 600
        thumbnails.totalCostLimit = Self.byteLimit
    }

    /// 展開後の画像のバイト数（キャッシュの cost に使う）
    nonisolated static func decodedCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// 表紙を入れ替えたので、メモリのサムネイルを捨てて次は読み直す（編集画面の「表紙を撮り直す」。T9）
    func invalidate(_ id: UUID) {
        thumbnails.removeObject(forKey: id as NSUUID)
        loading[id] = nil
        revisions[id, default: 0] += 1
    }

    func revision(for id: UUID) -> Int {
        revisions[id] ?? 0
    }

    /// すでにメモリにあるサムネイル（無ければ nil。読み込みはしない）
    func cachedThumbnail(for id: UUID) -> UIImage? {
        thumbnails.object(forKey: id as NSUUID)
    }

    /// サムネイルを読む。同じ本を同時に読まないよう、読み込み中のものは待ち合わせる
    func thumbnail(for id: UUID, in store: ImageStore) async -> UIImage? {
        if let image = cachedThumbnail(for: id) { return image }
        if let task = loading[id] { return await task.value }
        let url = store.thumbnailURL(for: id)
        let task = Task { await Self.decode(url) }
        loading[id] = task
        let image = await task.value
        loading[id] = nil
        if let image {
            thumbnails.setObject(image, forKey: id as NSUUID, cost: Self.decodedCost(of: image))
        } else {
            Self.logger.error("表紙のサムネイルを読めない: \(id.uuidString, privacy: .public)")
        }
        return image
    }

    /// 詳細画面用の原寸（キャッシュしない）
    func original(for id: UUID, in store: ImageStore) async -> UIImage? {
        await Self.decode(store.originalURL(for: id))
    }

    /// 画像ファイルを読み、描画の前にデコードを済ませる（スクロール中に主スレッドでデコードしない）
    @concurrent
    nonisolated static func decode(_ url: URL) async -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }
}

// MARK: - 棚表示のセル（書影1冊）

/// 棚表示（ピン型の並び）の書影1冊。表紙は切り抜かず、縦横比のまま高さをそろえる。外側ほど暗くする
final class ShelfCell: UICollectionViewCell {
    static let reuseID = "ShelfCell"

    private let coverView = UIImageView()
    private let shadeView = UIView()
    private(set) var bookID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        coverView.contentMode = .scaleToFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 2
        coverView.backgroundColor = UIColor(white: 0.93, alpha: 1)
        contentView.addSubview(coverView)
        shadeView.backgroundColor = .black
        shadeView.alpha = 0
        shadeView.isUserInteractionEnabled = false
        shadeView.layer.cornerRadius = 2
        contentView.addSubview(shadeView)
        // 中央の表紙の柔らかい影（design-brief §2-3。濃さはレイアウトで変える）
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 10)
        layer.shadowOpacity = 0
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使わない")
    }

    func configure(_ item: ShelfBookItem, index: Int, count: Int, store: ImageStore) {
        bookID = item.id
        // VoiceOver は題名で読み上げる（N5）
        accessibilityLabel = item.title
        accessibilityValue = "\(index + 1) / \(count)"
        accessibilityIdentifier = "shelf.book.\(index)"
        if let image = CoverImageCache.shared.cachedThumbnail(for: item.id) {
            setImage(image)
            return
        }
        setImage(nil)
        Task { [weak self] in
            let image = await CoverImageCache.shared.thumbnail(for: item.id, in: store)
            guard let self, self.bookID == item.id else { return }
            self.setImage(image)
        }
    }

    private func setImage(_ image: UIImage?) {
        coverView.image = image
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        bookID = nil
        coverView.image = nil
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        // 外側（小さい）ほど暗く、中央の1冊だけ柔らかい影を付ける
        let scale = layoutAttributes.transform.a
        shadeView.alpha = max(0, 1 - scale) * 0.3
        // 長押しで選んだ本は影を濃く・大きくする（design-brief §6）
        let lifted = layoutAttributes.zIndex >= PinLayout.liftedZIndex
        layer.shadowOpacity = lifted ? 0.4 : Float(max(0, (scale - 0.8) / 0.2) * 0.25)
        layer.shadowRadius = lifted ? 20 : 14
        layer.shadowOffset = CGSize(width: 0, height: lifted ? 18 : 10)
    }

    /// 枠の高さに合わせ、表紙の縦横比のまま幅を決めて、枠の中央に置く
    override func layoutSubviews() {
        super.layoutSubviews()
        let box = contentView.bounds
        var size = box.size
        if let image = coverView.image, image.size.height > 0 {
            let ratio = image.size.width / image.size.height
            size = CGSize(width: box.height * ratio, height: box.height)
            if size.width > box.width {
                size = CGSize(width: box.width, height: box.width / ratio)
            }
        }
        let frame = CGRect(
            x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        coverView.frame = frame
        shadeView.frame = frame
        layer.shadowPath = UIBezierPath(rect: frame).cgPath
    }
}

// MARK: - 棚の末尾の空き枠（B-1）

/// 棚の末尾の空き枠（F1-6 B）。タップするとこの棚を登録先にして登録を始める
final class ShelfSlotCell: UICollectionViewCell {
    static let reuseID = "ShelfSlotCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentConfiguration = UIHostingConfiguration { EmptyCoverBox(kind: .addBook) }.margins(.all, 0)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "この棚に本を追加"
        accessibilityIdentifier = "shelf.slot"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使わない")
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        contentView.alpha = 1 - max(0, 1 - layoutAttributes.transform.a) * 0.3
    }
}

/// 破線の空き枠（B-1 の「本を追加」、M-2 の買いたい本 0冊、本が1冊もないとき）
struct EmptyCoverBox: View {
    enum Kind {
        case addBook
        case wishlist
    }

    let kind: Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255))
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(BookshelfStyle.faint, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            switch kind {
            case .addBook:
                VStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(BookshelfStyle.ink))
                    Text("本を追加")
                        .font(BookshelfStyle.sans(15, .medium))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.ink)
                }
            case .wishlist:
                Image(systemName: "bookmark")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(BookshelfStyle.faint)
            }
        }
        .frame(width: 184, height: 264)
    }
}

// MARK: - グリッド表示のセル（I-1）

/// グリッド表示の1冊（表紙＋題名1行）。VoiceOver は題名で読み上げる（N5）。
/// 寸法は Figma I-1（51:29175）: 表紙の枠の高さ 146、表紙と題名の間 8、題名 Serif 13・高さ 18・中央ぞろえ
struct GridCellContent: View {
    static let coverHeight: CGFloat = 146
    static let titleHeight: CGFloat = 18
    static let spacing: CGFloat = 8
    static var height: CGFloat { coverHeight + spacing + titleHeight }

    let item: ShelfBookItem
    let index: Int
    let store: ImageStore
    /// VoiceOver の「メニュー」の操作（長押しの代わり。I-2）
    var onMenu: (() -> Void)?
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: Self.spacing) {
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
            Text(item.title)
                .font(BookshelfStyle.serif(13))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: Self.titleHeight)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("grid.book.\(index)")
        .accessibilityAction(named: "メニュー") { onMenu?() }
        .task(id: item.id) {
            image = CoverImageCache.shared.cachedThumbnail(for: item.id)
            if image == nil {
                image = await CoverImageCache.shared.thumbnail(for: item.id, in: store)
            }
        }
    }
}
