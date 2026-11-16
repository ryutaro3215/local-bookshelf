import SwiftData
import SwiftUI
import os

// MARK: - アプリの最初の画面（初回はチュートリアル、終われば閲覧画面）

/// 起動したときの画面。初回チュートリアル（F1-7）を終えていなければチュートリアル、終えていれば閲覧画面。
/// チュートリアルで最初の1冊を登録したら閲覧画面に切り替え、L-4 のシートを重ねる
struct AppRootView: View {
    let environment: AppEnvironment
    @State private var onboarding: OnboardingState
    /// L-4「最初の1冊が棚に並びました」
    @State private var showsFirstBook = false
    /// L-4 の「続けて登録する」を押した（シートが閉じきってから撮影を出す）
    @State private var continues = false
    @State private var flow: CaptureViewModel?

    init(environment: AppEnvironment) {
        self.environment = environment
        _onboarding = State(initialValue: OnboardingState.make(environment: environment))
    }

    var body: some View {
        if onboarding.isCompleted {
            ShelfScreen(environment: environment)
                .sheet(isPresented: $showsFirstBook, onDismiss: beginContinuedFlow) {
                    FirstBookSheet(
                        onContinue: {
                            continues = true
                            showsFirstBook = false
                        },
                        onBrowse: { showsFirstBook = false })
                }
                .fullScreenCover(item: $flow) { model in
                    RegistrationFlowView(model: model) { _ in flow = nil }
                }
        } else {
            OnboardingView(environment: environment) {
                onboarding.complete()
                showsFirstBook = true
            }
        }
    }

    /// 「続けて登録する」: 直前に使った棚（チュートリアルで選んだ棚）を登録先に、カメラから始める
    private func beginContinuedFlow() {
        guard continues else { return }
        continues = false
        let destination: Shelf
        do {
            destination = try environment.recent.initialShelf(in: environment.store)
        } catch {
            OnboardingView.logger.error("登録先の棚を決められない: \(error.localizedDescription, privacy: .public)")
            return
        }
        flow = CaptureViewModel(
            store: environment.store, camera: environment.makeCamera(), destination: destination,
            recent: environment.recent, screen: .camera)
    }
}

// MARK: - 初回チュートリアル（L-1・L-2・O-1・L-3）

/// 初回チュートリアル（F1-7・design-brief §5「初回」）。
/// ようこそ（L-1）→ 最初の棚（L-2）→ カメラの許可（O-1。まだ許可を聞いていないときだけ）→ 撮影（案内つき。L-3）
/// → 登録待ちの一覧 → 登録。スキップはできず、1冊登録するまで閲覧画面に進めない
struct OnboardingView: View {
    static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Onboarding")

    enum Step: Equatable {
        case welcome
        case shelf
        case permission
        case capture
    }

    let environment: AppEnvironment
    /// 1冊以上登録できた
    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var destination: Shelf?
    @State private var camera: (any CameraSource)?
    @State private var flow: CaptureViewModel?

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomePage { step = .shelf }
                    .transition(.opacity)
            case .shelf:
                FirstShelfPage(shelves: featuredShelves, selection: $destination) { chooseShelf() }
                    .transition(.opacity)
            case .permission:
                CameraPermissionPage(
                    onAllow: {
                        Task {
                            _ = await camera?.requestAccess()
                            startFlow(.camera)
                        }
                    },
                    onLibrary: { startFlow(.library) }
                )
                .transition(.opacity)
            case .capture:
                if let flow {
                    RegistrationFlowView(model: flow) { registered in
                        if registered > 0 {
                            onFinished()
                        } else {
                            // 登録せずに閉じたら、棚を選ぶところへ戻る（チュートリアルは抜けない）
                            self.flow = nil
                            step = .shelf
                        }
                    }
                    // 最初の1枚が登録待ちに入ったら、題名を確かめる一覧へ進む
                    .onChange(of: flow.items.count) { old, new in
                        if old == 0 && new > 0 && flow.screen == .camera {
                            flow.screen = .pending
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: step)
        .onAppear {
            if destination == nil {
                destination = featuredShelves.first { $0.kind == .unsorted } ?? featuredShelves.first
            }
        }
    }

    /// L-2 に並べる棚（Figma L-2 の9つ。初期ジャンルの名前で選ぶ）。見つからなければ、買いたい本以外のすべての棚
    private var featuredShelves: [Shelf] {
        let all: [Shelf]
        do {
            all = try environment.store.shelves().filter { $0.kind != .wishlist }
        } catch {
            Self.logger.error("棚の一覧を読めない: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let featured = all.filter { $0.kind == .unsorted || FirstShelfPage.featuredNames.contains($0.name) }
        return featured.count > 1 ? featured : all
    }

    private func chooseShelf() {
        let camera = environment.makeCamera()
        self.camera = camera
        var asks = camera.authorization == .notDetermined
        #if DEBUG
            // UIテスト・スクリーンショット用: 許可済みの合成カメラでも O-1 を出す
            if ProcessInfo.processInfo.arguments.contains("-UITestCameraPermission") { asks = true }
        #endif
        if asks {
            step = .permission
        } else {
            startFlow(.camera)
        }
    }

    private func startFlow(_ start: RegistrationStart) {
        guard let destination else { return }
        let camera = camera ?? environment.makeCamera()
        let model = CaptureViewModel(
            store: environment.store, camera: camera, destination: destination, recent: environment.recent,
            screen: start == .camera ? .camera : .pending)
        model.opensLibraryOnAppear = start == .library
        model.showsShutterHint = true
        flow = model
        step = .capture
    }
}

// MARK: - 部品

/// 下の点（3つ。今のページは横長の黒）
private struct PageDots: View {
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == index ? BookshelfStyle.ink : Color(red: 0xDA / 255, green: 0xDA / 255, blue: 0xDA / 255))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("ページ")
        .accessibilityValue("\(index + 1) / 3")
        .accessibilityIdentifier("onboarding.dots")
    }
}

/// 主ボタン（INK の地・白文字・高さ 52）
private struct PrimaryButton: View {
    let title: String
    let id: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BookshelfStyle.sans(16, .medium))
                .tracking(0.5)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(BookshelfStyle.ink.opacity(enabled ? 1 : 0.3)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .accessibilityIdentifier(id)
    }
}

// MARK: L-1 ようこそ

private struct WelcomePage: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            SampleCoverFan()
                .frame(height: 300)
                .accessibilityHidden(true)
            Text("local-bookshelf")
                .font(BookshelfStyle.sans(13))
                .tracking(2)
                .foregroundStyle(BookshelfStyle.faint)
                .padding(.top, 30)
            Text("撮るだけで、自分の本棚に。")
                .font(BookshelfStyle.sans(24, .medium, relativeTo: .title2))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.welcome")
            Text("表紙を撮ると、本棚に並びます。\n題名で探せて、買った月ごとにも見返せます。")
                .font(BookshelfStyle.sans(13))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .padding(.top, 18)
            Spacer(minLength: 24)
            PageDots(index: 0)
            PrimaryButton(title: String(localized: "最初の1冊を登録する"), id: "onboarding.start", action: onStart)
                .padding(.top, 46)
            Text("データはこの iPhone の中だけに保存されます")
                .font(BookshelfStyle.sans(11))
                .foregroundStyle(BookshelfStyle.faint)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.ignoresSafeArea())
    }
}

/// L-1 の書影の並び（閲覧画面と同じピン型。表紙は架空の題名を描いた見本で、実在の本は使わない）
private struct SampleCoverFan: View {
    private static let titlesJa = [
        "灰色の標本箱", "遠い観測所", "静かな温室", "冬の地図", "白い回廊", "夜更けの灯台", "小さな惑星", "古い郵便局", "青い時計",
    ]
    /// 英語表示のときの見本の題名（架空。T15）
    private static let titlesEn = [
        "The Gray Specimen Box", "A Distant Observatory", "The Quiet Greenhouse", "Winter Atlas", "The White Corridor",
        "Midnight Lighthouse", "A Small Planet", "The Old Post Office", "The Blue Clock",
    ]
    private static var titles: [String] { InitialGenres.displaysInEnglish ? titlesEn : titlesJa }
    private static let ratios: [CGFloat] = [0.70, 0.66, 0.72, 0.68, 0.75, 0.64, 0.70, 0.67, 0.73]
    private static let tones: [Double] = [0.30, 0.82, 0.55, 0.90, 0.42, 0.70, 0.25, 0.86, 0.60]

    var body: some View {
        ZStack {
            ForEach(-4...4, id: \.self) { offset in
                let far = abs(offset)
                let index = offset + 4
                let scale = PinLayout.scales[far]
                SampleCover(
                    title: Self.titles[index], tone: Self.tones[index],
                    width: PinLayout.bookSize.height * Self.ratios[index] * scale,
                    height: PinLayout.bookSize.height * scale
                )
                .brightness(-0.04 * Double(far))
                .shadow(color: .black.opacity(far == 0 ? 0.25 : 0.1), radius: far == 0 ? 18 : 6, y: far == 0 ? 12 : 3)
                .offset(x: CGFloat(offset.signum()) * PinLayout.offsets[far], y: -PinLayout.lifts[far])
                .zIndex(Double(10 - far))
            }
        }
    }
}

private struct SampleCover: View {
    let title: String
    let tone: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let dark = tone < 0.5
        ZStack {
            Color(white: tone)
            VStack(spacing: 0) {
                Text(title)
                    .font(.custom("Noto Serif JP", size: width * 0.12).weight(.semibold))
                    .foregroundStyle(dark ? Color.white : BookshelfStyle.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, width * 0.1)
                    .padding(.top, height * 0.18)
                Spacer()
                Rectangle()
                    .fill(Color(white: dark ? 0.85 : 0.2).opacity(0.8))
                    .frame(height: height * 0.1)
                    .padding(.bottom, height * 0.14)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: L-2 最初の棚を選ぶ

private struct FirstShelfPage: View {
    /// Figma L-2 に並ぶ棚（初期ジャンルの日本語名）。ほかの棚は撮影画面の「登録先」から選べる
    static let featuredNames: Set<String> = [
        "小説", "エッセイ", "漫画", "哲学・思想", "歴史", "心理", "経済・経営", "ビジネス・自己啓発",
    ]

    let shelves: [Shelf]
    @Binding var selection: Shelf?
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最初の本を置く棚を選んでください")
                .font(BookshelfStyle.sans(20, .medium, relativeTo: .title3))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.shelf.heading")
            Text("あとから変えられます。迷ったら「未分類」でも大丈夫です")
                .font(BookshelfStyle.sans(12))
                .foregroundStyle(BookshelfStyle.sub)
                .padding(.horizontal, 24)
                .padding(.top, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.category.id) { group in
                        Text(group.category.displayName)
                            .font(BookshelfStyle.sans(11, .medium))
                            .tracking(1)
                            .foregroundStyle(BookshelfStyle.faint)
                            .padding(.horizontal, 26)
                            .padding(.top, 14)
                            .padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.shelves, id: \.persistentModelID) { shelf in
                            row(shelf)
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            PageDots(index: 1)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            PrimaryButton(
                title: selection.map { String(localized: "\($0.displayName) で撮影する") }
                    ?? String(localized: "棚を選んでください"),
                id: "onboarding.shelf.confirm",
                enabled: selection != nil, action: onConfirm
            )
            .padding(.top, 30)
            .padding(.bottom, 42)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private func row(_ shelf: Shelf) -> some View {
        let selected = shelf.persistentModelID == selection?.persistentModelID
        return Button {
            selection = shelf
        } label: {
            HStack {
                Text(shelf.displayName)
                    .font(BookshelfStyle.serif(16))
                    .tracking(0.5)
                    .foregroundStyle(shelf.kind == .unsorted && !selected ? BookshelfStyle.sub : BookshelfStyle.ink)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? BookshelfStyle.fill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel(shelf.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.shelf.row.\(shelf.name)")
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

// MARK: O-1 カメラの許可（説明）

private struct CameraPermissionPage: View {
    let onAllow: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: "camera")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(BookshelfStyle.ink)
                .frame(width: 88, height: 88)
                .background(Circle().fill(BookshelfStyle.fill))
                .accessibilityHidden(true)
            Text("表紙を撮るために\nカメラを使います")
                .font(BookshelfStyle.sans(20, .medium, relativeTo: .title3))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .padding(.top, 44)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.permission.heading")
            Text("撮った写真は、この iPhone の中だけに保存され、\nどこにも送信されません。")
                .font(BookshelfStyle.sans(13))
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .padding(.top, 26)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            PageDots(index: 2)
            PrimaryButton(title: String(localized: "カメラを許可する"), id: "onboarding.permission.allow", action: onAllow)
                .padding(.top, 46)
            Button(action: onLibrary) {
                Text("写真ライブラリから選ぶ")
                    .font(BookshelfStyle.sans(14, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.sub)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .accessibilityIdentifier("onboarding.permission.library")
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - L-4 最初の1冊が並んだ

/// 最初の1冊を登録して閲覧画面に戻ったときのシート（L-4）
private struct FirstBookSheet: View {
    let onContinue: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("最初の1冊が棚に並びました")
                .font(BookshelfStyle.sans(18, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 34)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("firstBook.heading")
            Text("← → で本をめくり、↑ ↓ で棚をかえます。\n次の本は、右下の「＋」から登録できます。")
                .font(BookshelfStyle.sans(13))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .padding(.top, 14)
            PrimaryButton(title: String(localized: "続けて登録する"), id: "firstBook.continue", action: onContinue)
                .padding(.top, 26)
            Button(action: onBrowse) {
                Text("本棚を見る")
                    .font(BookshelfStyle.sans(15, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(BookshelfStyle.fill))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .accessibilityIdentifier("firstBook.browse")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(330)])
        .presentationBackground(Color.white)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }
}
