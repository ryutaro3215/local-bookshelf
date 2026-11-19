import Photos
import SwiftUI
import UIKit
import os

// MARK: - 共有の依頼（何を共有できるか）

/// 共有する範囲の候補1つ（ジャンル別は「この棚」だけ、購入月別は「この日／この月」・年では「この日／この年」。F8-5）
struct ShareOption: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case genre
        case day
        case month
        case year
    }

    let kind: Kind
    let content: ShareContent
    var id: Kind { kind }

    /// 範囲の選択の行の名前（K-3）
    var label: LocalizedStringKey {
        switch kind {
        case .genre: "この棚"
        case .day: "この日"
        case .month: "この月"
        case .year: "この年"
        }
    }

    /// 範囲の選択の行の補足（「10月20日・3冊」「2026年10月・9冊」）
    var detail: String {
        let count = content.total
        switch content.scope {
        case .day(let date):
            return String(localized: "\(ShareText.shortDay(date))・\(count)冊")
        default:
            return String(localized: "\(ShareText.period(of: content.scope))・\(count)冊")
        }
    }

    /// 共有先のシートの見出し（K-2「この棚を共有」）
    var title: LocalizedStringKey {
        switch kind {
        case .genre: "この棚を共有"
        case .day: "この日を共有"
        case .month: "この月を共有"
        case .year: "この年を共有"
        }
    }

    /// 共有先のシートの補足（K-2「哲学・思想・9冊（購入済みの本だけ）」）
    var summary: String {
        String(localized: "\(ShareText.period(of: content.scope))・\(content.total)冊（購入済みの本だけ）")
    }
}

/// 共有マークを押したときの依頼（範囲の候補。1つなら範囲の選択は出さない）
struct ShareRequest: Identifiable {
    let id = UUID()
    let options: [ShareOption]

    /// ジャンル別: その棚の購入済みの本（K-2）
    @MainActor
    static func genre(name: String, books: [Book]) -> ShareRequest {
        ShareRequest(options: [ShareOption(kind: .genre, content: .make(scope: .genre(name), books: books))])
    }

    /// 購入月別: 見ている本の日と、その月（年）（K-3）。見ている本が無ければ（グリッド）月（年）だけ
    @MainActor
    static func purchase(group: PurchaseGroup, focused: Book?, calendar: Calendar = .current) -> ShareRequest {
        var options: [ShareOption] = []
        if let date = focused?.purchaseDate {
            let day = group.books.filter { book in
                book.purchaseDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            }
            options.append(ShareOption(kind: .day, content: .make(scope: .day(date), books: day, calendar: calendar)))
        }
        if let month = group.month {
            options.append(
                ShareOption(
                    kind: .month,
                    content: .make(
                        scope: .month(year: group.year, month: month), books: group.books, calendar: calendar)))
        } else {
            options.append(
                ShareOption(
                    kind: .year, content: .make(scope: .year(group.year), books: group.books, calendar: calendar)))
        }
        return ShareRequest(options: options)
    }
}

// MARK: - 共有先（F8-7）

/// 共有先。フィード・X・写真に保存は 4:5、ストーリーズは 9:16（F8-3）
enum ShareDestination: String, Hashable, CaseIterable {
    case feed
    case story
    case x
    case photos

    var format: ShareFormat { self == .story ? .story : .portrait }

    /// 共有先のシートの名前（2行）
    var name: LocalizedStringKey {
        switch self {
        case .feed: "Instagram\nフィード"
        case .story: "Instagram\nストーリーズ"
        case .x: "X の\nポスト"
        case .photos: "写真に\n保存"
        }
    }

    var icon: String {
        switch self {
        case .feed: "camera"
        case .story: "iphone"
        case .x: "bubble.left"
        case .photos: "arrow.down.to.line"
        }
    }

    var ratio: String { self == .story ? "9:16" : "4:5" }

    /// プレビューの見出し（K-4「ストーリーズ（9:16）」・K-5「X のポスト（4:5）」）
    var previewTitle: LocalizedStringKey {
        switch self {
        case .feed: "フィード（4:5）"
        case .story: "ストーリーズ（9:16）"
        case .x: "X のポスト（4:5）"
        case .photos: "写真に保存（4:5）"
        }
    }

    /// 主ボタン（写真に保存は副ボタンだけ）
    var postLabel: LocalizedStringKey? {
        switch self {
        case .feed: "フィードに投稿"
        case .story: "ストーリーズに投稿"
        case .x: "X に投稿"
        case .photos: nil
        }
    }
}

// MARK: - 共有の流れ（K-2〜K-5）

/// 共有の流れ（F8。K-3 範囲を選ぶ → K-2 共有先 → K-4・K-5 プレビュー → 投稿・写真に保存）。シートで出す
struct ShareFlowView: View {
    let request: ShareRequest
    let images: ImageStore
    let onClose: () -> Void

    private enum Step: Hashable {
        case destinations(ShareOption.Kind)
        case preview(ShareOption.Kind, ShareDestination)
    }

    @State private var path: [Step] = []
    @State private var selected: ShareOption.Kind
    @State private var renders = ShareRenders()
    @State private var detent: PresentationDetent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let rangeDetent = PresentationDetent.height(470)
    /// 範囲を選ぶシートの高さ（最大の文字サイズでは画面いっぱい。N5）
    private var rangeDetent: PresentationDetent {
        dynamicTypeSize.isAccessibilitySize ? .large : Self.rangeDetent
    }

    init(request: ShareRequest, images: ImageStore, onClose: @escaping () -> Void) {
        self.request = request
        self.images = images
        self.onClose = onClose
        _selected = State(initialValue: request.options.first?.kind ?? .genre)
        _detent = State(initialValue: request.options.count > 1 ? Self.rangeDetent : .large)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if request.options.count > 1 {
                    ShareRangeStep(
                        options: request.options, selected: $selected,
                        onNext: { path.append(.destinations(selected)) },
                        onCancel: onClose)
                } else if let option = request.options.first {
                    destinations(option)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .destinations(let kind):
                    if let option = option(kind) {
                        destinations(option)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                case .preview(let kind, let destination):
                    if let option = option(kind) {
                        SharePreviewStep(
                            option: option, destination: destination, images: images, renders: renders,
                            onBack: { path.removeLast() })
                    }
                }
            }
        }
        .presentationDetents(request.options.count > 1 ? [Self.rangeDetent, .large] : [.large], selection: $detent)
        .onAppear {
            if request.options.count > 1 { detent = rangeDetent }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        // Figma の K-2・K-3 は白い地（iOS 26 の半透明のシートにしない）
        .presentationBackground(BookshelfStyle.surface)
        // 範囲を選んだら共有先・プレビューは画面いっぱいに広げる
        .onChange(of: path) { _, steps in
            detent = steps.isEmpty && request.options.count > 1 ? rangeDetent : .large
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share.sheet")
    }

    private func option(_ kind: ShareOption.Kind) -> ShareOption? {
        request.options.first { $0.kind == kind }
    }

    private func destinations(_ option: ShareOption) -> some View {
        ShareDestinationStep(
            option: option, images: images, renders: renders,
            onSelect: { path.append(.preview(option.kind, $0)) },
            onCancel: onClose)
    }
}

/// 作った共有画像を、範囲と縦横比ごとに覚えておく（行き来しても作り直さない）
@MainActor
@Observable
final class ShareRenders {
    private(set) var images: [Key: ShareImage] = [:]
    private(set) var failed: Set<Key> = []

    struct Key: Hashable {
        let content: ShareContent
        let format: ShareFormat
    }

    func image(for content: ShareContent, format: ShareFormat) -> ShareImage? {
        images[Key(content: content, format: format)]
    }

    func hasFailed(_ content: ShareContent, format: ShareFormat) -> Bool {
        failed.contains(Key(content: content, format: format))
    }

    func render(_ content: ShareContent, format: ShareFormat, images store: ImageStore) async {
        let key = Key(content: content, format: format)
        guard images[key] == nil else { return }
        do {
            images[key] = try await ShareRenderer.render(content, format: format, images: store)
            failed.remove(key)
        } catch {
            failed.insert(key)
        }
    }
}

// MARK: - K-3 範囲を選ぶ

/// 購入月別で共有する範囲を選ぶ（K-3）
private struct ShareRangeStep: View {
    let options: [ShareOption]
    @Binding var selected: ShareOption.Kind
    let onNext: () -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 最大の文字サイズでは、範囲の名前の下に補足を置き、全体をスクロールできるようにする（N5）
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share.range")
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text("共有する範囲")
                .font(BookshelfStyle.sans(18, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 30)
                .accessibilityAddTraits(.isHeader)
            Text("購入済みの本だけを1枚の画像にします")
                .font(BookshelfStyle.sans(12))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            VStack(spacing: 12) {
                ForEach(options) { option in
                    row(option)
                }
            }
            .padding(.top, 22)
            Button(action: onNext) {
                Text("次へ")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.onInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(BookshelfStyle.ink))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
            .accessibilityIdentifier("share.next")
            Button(action: onCancel) {
                Text("キャンセル")
                    .font(BookshelfStyle.sans(15, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("share.cancel")
        }
        .padding(.horizontal, 20)
    }

    private func row(_ option: ShareOption) -> some View {
        let isOn = option.kind == selected
        return Button {
            selected = option.kind
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(isOn ? BookshelfStyle.ink : BookshelfStyle.checkOff, lineWidth: isOn ? 0 : 1.5)
                        .background(Circle().fill(isOn ? BookshelfStyle.ink : BookshelfStyle.surface))
                        .frame(width: 20, height: 20)
                    if isOn {
                        Circle().fill(BookshelfStyle.onInk).frame(width: 7, height: 7)
                    }
                }
                let layout =
                    isLarge
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    Text(option.label)
                        .font(BookshelfStyle.sans(16, .medium))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.ink)
                    Text(verbatim: option.detail)
                        .font(BookshelfStyle.sans(12))
                        .tracking(0.3)
                        .foregroundStyle(BookshelfStyle.sub)
                        .lineLimit(isLarge ? nil : 1)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, isLarge ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isOn ? BookshelfStyle.surface : BookshelfStyle.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isOn ? BookshelfStyle.ink : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("share.range.\(option.kind.rawValue)")
    }
}

// MARK: - K-2 共有先を選ぶ

/// 共有先を選ぶシート（K-2）。上に 4:5 の画像の縮小、下に4つの共有先
private struct ShareDestinationStep: View {
    let option: ShareOption
    let images: ImageStore
    let renders: ShareRenders
    let onSelect: (ShareDestination) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 最大の文字サイズでは、共有先を4つ横に並べず1行ずつにする（名前を省略しない。N5）
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text(option.title)
                        .font(BookshelfStyle.sans(18, .medium))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.ink)
                        .padding(.top, 30)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("share.title")
                    Text(verbatim: option.summary)
                        .font(BookshelfStyle.sans(12))
                        .tracking(0.5)
                        .foregroundStyle(BookshelfStyle.sub)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("share.summary")
                    SharedImageView(
                        content: option.content, format: .portrait, images: images, renders: renders, width: 152
                    )
                    .padding(.top, 20)
                    Text("共有先")
                        .font(BookshelfStyle.sans(11, .medium))
                        .tracking(1)
                        .foregroundStyle(BookshelfStyle.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 44)
                        .padding(.horizontal, 24)
                    if isLarge {
                        VStack(spacing: 10) {
                            ForEach(ShareDestination.allCases, id: \.self) { destination in
                                row(destination)
                            }
                        }
                        .padding(.top, 14)
                        .padding(.horizontal, 20)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(ShareDestination.allCases, id: \.self) { destination in
                                tile(destination)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 14)
                        .padding(.horizontal, 12)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(action: onCancel) {
                Text("キャンセル")
                    .font(BookshelfStyle.sans(15, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(BookshelfStyle.fill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .accessibilityIdentifier("share.cancel")
        }
        .background(BookshelfStyle.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share.destinations")
    }

    /// 最大の文字サイズの共有先の1行（アイコン・名前・縦横比）
    private func row(_ destination: ShareDestination) -> some View {
        Button {
            onSelect(destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: destination.icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    // 名前は2行の形（「Instagram\nフィード」）なので、1行の形にしない（文言をそのまま使う）
                    Text(destination.name)
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.ink)
                    Text(verbatim: destination.ratio)
                        .font(BookshelfStyle.sans(10))
                        .foregroundStyle(BookshelfStyle.faint)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("share.destination.\(destination.rawValue)")
    }

    private func tile(_ destination: ShareDestination) -> some View {
        Button {
            onSelect(destination)
        } label: {
            VStack(spacing: 0) {
                Image(systemName: destination.icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
                Text(destination.name)
                    .font(BookshelfStyle.sans(12))
                    .tracking(0.3)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BookshelfStyle.ink)
                    .padding(.top, 10)
                Text(verbatim: destination.ratio)
                    .font(BookshelfStyle.sans(10))
                    .foregroundStyle(BookshelfStyle.faint)
                    .padding(.top, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("share.destination.\(destination.rawValue)")
    }
}

// MARK: - K-4・K-5 プレビュー

/// 共有先を選んだあとのプレビュー（K-4 ストーリーズ 9:16・K-5 フィード／X 4:5）。主ボタンで投稿、副ボタンで写真に保存
private struct SharePreviewStep: View {
    let option: ShareOption
    let destination: ShareDestination
    let images: ImageStore
    let renders: ShareRenders
    let onBack: () -> Void

    @State private var status: LocalizedStringKey?
    @State private var activityImage: ActivityImage?
    @State private var isWorking = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shareImage: ShareImage? { renders.image(for: option.content, format: destination.format) }

    var body: some View {
        VStack(spacing: 0) {
            // 最大の文字サイズでは「‹ 戻る」の下に見出しを置く（重ならないように。N5）
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 4) {
                        backRow
                        previewTitle
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else {
                    ZStack {
                        previewTitle
                            .lineLimit(1)
                            .padding(.horizontal, 90)
                        backRow
                    }
                }
            }
            .padding(.top, 14)
            GeometryReader { geometry in
                let width = previewWidth(in: geometry.size)
                VStack(spacing: 14) {
                    SharedImageView(
                        content: option.content, format: destination.format, images: images, renders: renders,
                        width: width, showsStoryGuides: destination == .story)
                    if destination != .story {
                        Text("フィード・X・保存は 4:5（1080×1350）")
                            .font(BookshelfStyle.sans(12))
                            .tracking(0.3)
                            .foregroundStyle(BookshelfStyle.faint)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
            }
            if let status {
                Text(status)
                    .font(BookshelfStyle.sans(12))
                    .tracking(0.3)
                    .foregroundStyle(BookshelfStyle.sub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("share.status")
            }
            VStack(spacing: 12) {
                if let post = destination.postLabel {
                    Button(action: postAction) {
                        Text(post)
                            .font(BookshelfStyle.sans(16, .medium))
                            .tracking(0.5)
                            .foregroundStyle(BookshelfStyle.onInk)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Capsule().fill(BookshelfStyle.ink))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("share.post")
                }
                Button(action: saveAction) {
                    Text("写真に保存")
                        .font(BookshelfStyle.sans(destination == .photos ? 16 : 15, .medium))
                        .tracking(0.5)
                        .foregroundStyle(destination == .photos ? BookshelfStyle.onInk : BookshelfStyle.ink)
                        .frame(maxWidth: .infinity, minHeight: destination == .photos ? 52 : 50)
                        .background(Capsule().fill(destination == .photos ? BookshelfStyle.ink : BookshelfStyle.fill))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("share.save")
            }
            .disabled(shareImage == nil || isWorking)
            .opacity(shareImage == nil ? 0.4 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(BookshelfStyle.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activityImage) { item in
            ActivityView(image: item.image)
                .presentationDetents([.medium, .large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share.preview")
    }

    private var previewTitle: some View {
        Text(destination.previewTitle)
            .font(BookshelfStyle.sans(16, .medium))
            .tracking(0.5)
            .foregroundStyle(BookshelfStyle.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("share.preview.title")
    }

    private var backRow: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .regular))
                    Text("戻る")
                        .font(BookshelfStyle.sans(15))
                }
                .foregroundStyle(BookshelfStyle.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("share.back")
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    /// 画面に収まる大きさ（ストーリーズは縦長なので高さで決める）
    private func previewWidth(in size: CGSize) -> CGFloat {
        let ratio = destination.format.size.width / destination.format.size.height
        let byHeight = (size.height - 60) * ratio
        return max(min(destination == .story ? 300 : 320, byHeight, size.width - 40), 120)
    }

    private func postAction() {
        guard let shareImage else { return }
        status = nil
        switch destination {
        case .story:
            isWorking = true
            Task {
                let outcome = await InstagramStoriesSharer.share(imageData: shareImage.data)
                isWorking = false
                switch outcome {
                case .opened:
                    break
                case .missingAppID, .unavailable:
                    // ストーリーズへ直接渡せないときは、共有シートから Instagram を選んでもらう
                    status = "Instagram へ直接渡せないため、共有シートを開きました"
                    activityImage = ActivityImage(image: shareImage.image)
                }
            }
        case .feed, .x:
            // フィード・X は OS の共有シートから各アプリへ渡す（F8-7）
            activityImage = ActivityImage(image: shareImage.image)
        case .photos:
            saveAction()
        }
    }

    private func saveAction() {
        guard let shareImage else { return }
        isWorking = true
        status = nil
        Task {
            let outcome = await PhotoSaver.save(shareImage.data)
            isWorking = false
            switch outcome {
            case .saved: status = "写真に保存しました"
            case .denied: status = "写真への追加が許可されていません。設定アプリで許可できます"
            case .failed: status = "写真に保存できませんでした"
            }
        }
    }
}

// MARK: - 画像の表示（縮小）

/// 生成した共有画像を縮小して見せる。作り終えるまでは地の色の枠と読み込み中の印
private struct SharedImageView: View {
    let content: ShareContent
    let format: ShareFormat
    let images: ImageStore
    let renders: ShareRenders
    let width: CGFloat
    var showsStoryGuides = false

    var body: some View {
        let size = format.size
        let height = width * size.height / size.width
        ZStack {
            if let image = renders.image(for: content, format: format) {
                Image(uiImage: image.image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                if showsStoryGuides {
                    storyGuides(height: height)
                }
            } else {
                ShareFonts.background
                if renders.hasFailed(content, format: format) {
                    Text("画像を作れませんでした")
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.sub)
                } else {
                    ProgressView()
                }
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共有する画像")
        .accessibilityValue(renders.image(for: content, format: format) == nil ? "作成中" : "")
        .accessibilityIdentifier(
            renders.image(for: content, format: format) == nil ? "share.image.loading" : "share.image"
        )
        .task(id: ShareRenders.Key(content: content, format: format)) {
            await renders.render(content, format: format, images: images)
        }
    }

    /// ストーリーズの上 14%・下 20% に重なる表示の案内（プレビューだけ。画像には入れない）
    private func storyGuides(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            guide("上 14%：ストーリーズの表示と重なる")
                .frame(height: height * 0.14)
            Spacer(minLength: 0)
            guide("下 20%：返信欄と重なる")
                .frame(height: height * 0.20)
        }
    }

    private func guide(_ text: LocalizedStringKey) -> some View {
        ZStack {
            // 共有画像（外観によらず明るい）の上に重ねるので、外観で色を変えない
            Color(red: 0xE0 / 255, green: 0xDC / 255, blue: 0xD8 / 255).opacity(0.92)
            Text(text)
                .font(BookshelfStyle.sans(10))
                .foregroundStyle(ShareFonts.note)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
        }
        .overlay(Rectangle().stroke(BookshelfStyle.faint, lineWidth: 0.5))
    }
}

// MARK: - OS の共有シート・写真に保存

/// 共有シートに渡す画像
private struct ActivityImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// OS の共有シート（フィード・X・ストーリーズの代わり）
private struct ActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 共有画像を写真に保存する。写真ライブラリへの「追加のみ」の権限だけを求める（読み取りは求めない。S4）。
/// performChanges のクロージャは写真ライブラリの裏のキューで動くので、MainActor に隔離しない
nonisolated enum PhotoSaver {
    enum Outcome: Equatable {
        case saved
        case denied
        case failed
    }

    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Share")

    static func save(_ data: Data) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            logger.notice("写真への追加が許可されていない")
            return .denied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            logger.error("写真に保存できない: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}
