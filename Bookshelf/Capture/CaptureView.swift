import CoreText
import PhotosUI
import SwiftData
import SwiftUI
import os

// MARK: - デザインのトークン（.dev/design-brief.md §2）

/// 色・書体（design-brief §2）。T5 で撮影登録の画面のために置いた。T6 で共通のトークン定義に移す想定
nonisolated enum BookshelfStyle {
    static let ink = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255)
    static let sub = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x8E / 255)
    static let faint = Color(red: 0xBD / 255, green: 0xBD / 255, blue: 0xBD / 255)
    static let fill = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
    static let line = Color(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255)
    static let panelLine = Color(red: 0xED / 255, green: 0xED / 255, blue: 0xED / 255)
    static let checkOff = Color(red: 0xC4 / 255, green: 0xC4 / 255, blue: 0xC4 / 255)
    static let grabber = Color(red: 0xDA / 255, green: 0xDA / 255, blue: 0xDA / 255)
    /// 撮影画面・四隅調整の地とボタン
    static let cameraBackground = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255)
    static let cameraControl = Color.white.opacity(0.14)

    /// 同梱の書体（SIL Open Font License。Bookshelf/Resources/Fonts）
    static let fontFiles = ["NotoSansJP-VariableFont_wght", "NotoSerifJP-VariableFont_wght"]
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Fonts")

    /// 同梱の書体をこのアプリの中だけで使えるようにする（起動時に1回）
    static func registerFonts() {
        for name in fontFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                logger.error("書体のファイルが無い: \(name, privacy: .public)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let message = error?.takeRetainedValue().localizedDescription ?? "不明"
                logger.error("書体を登録できない: \(name, privacy: .public) \(message, privacy: .public)")
            }
        }
    }

    /// Noto Sans JP（本文 400・見出しとボタン 500）。Dynamic Type に合わせて大きさが変わる
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body)
        -> Font
    {
        .custom("Noto Sans JP", size: size, relativeTo: style).weight(weight)
    }

    /// Noto Serif JP 600（ジャンル名・棚の名前・本の題名）
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Noto Serif JP", size: size, relativeTo: style).weight(.semibold)
    }
}

// MARK: - 登録の入口（A-2: 登録方法の選択シート）

/// 登録の始め方（F1-6: 撮影／ライブラリ。どちらも登録待ちの一覧に入る）
enum RegistrationStart: Equatable {
    case camera
    case library
}

/// 登録方法の選択シート（A-2）。入口（下部バーの＋・棚の末尾の空き枠）から出す。登録先の棚をここで変えられる（F1-5）
struct RegistrationMethodSheet: View {
    let shelves: [Shelf]
    @Binding var destination: Shelf
    let onSelect: (RegistrationStart) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("本を登録")
                .font(BookshelfStyle.sans(18, .medium))
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 28)
            DestinationMenu(shelves: shelves, destination: $destination, dark: false)
                .padding(.top, 12)
            VStack(spacing: 12) {
                methodCard(
                    icon: "camera", title: "写真を撮る", detail: "表紙を撮って、続けて登録", id: "register.camera"
                ) { onSelect(.camera) }
                methodCard(
                    icon: "photo", title: "ライブラリから選ぶ", detail: "撮影済みの写真から登録（複数選択可）",
                    id: "register.library"
                ) { onSelect(.library) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            Button("キャンセル", action: onCancel)
                .font(BookshelfStyle.sans(16, .medium))
                .foregroundStyle(BookshelfStyle.sub)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .accessibilityIdentifier("register.cancel")
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(420)])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private func methodCard(icon: String, title: String, detail: String, id: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BookshelfStyle.sans(16, .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                    Text(detail)
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.sub)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BookshelfStyle.faint)
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// 「登録先 ○○ ▾」のチップ。タップで棚を選ぶ（買いたい本は選べない）
struct DestinationMenu: View {
    let shelves: [Shelf]
    @Binding var destination: Shelf
    /// 撮影画面（暗い地）か
    let dark: Bool

    var body: some View {
        Menu {
            ForEach(shelves) { shelf in
                Button {
                    destination = shelf
                } label: {
                    if shelf.persistentModelID == destination.persistentModelID {
                        Label(shelf.name, systemImage: "checkmark")
                    } else {
                        Text(shelf.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("登録先")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(dark ? Color.white.opacity(0.55) : BookshelfStyle.sub)
                Text(destination.name)
                    .font(BookshelfStyle.serif(13))
                    .foregroundStyle(dark ? Color.white : BookshelfStyle.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(dark ? Color.white.opacity(0.55) : BookshelfStyle.sub)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(dark ? BookshelfStyle.cameraControl : BookshelfStyle.fill))
        }
        .accessibilityIdentifier("register.destination")
        .accessibilityLabel("登録先")
        .accessibilityValue(destination.name)
    }
}

// MARK: - 登録フロー（撮影 → 登録待ちの一覧 → 登録）

/// 撮影登録フローの入れ物。カメラ（A-3）と登録待ちの一覧（C）を切り替え、検出に失敗した1枚は N 画面を重ねる
struct RegistrationFlowView: View {
    @State private var model: CaptureViewModel
    let onClose: (_ registered: Int) -> Void

    init(model: CaptureViewModel, onClose: @escaping (_ registered: Int) -> Void) {
        _model = State(initialValue: model)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            switch model.screen {
            case .camera:
                CaptureView(model: model) {
                    // 撮った本があれば一覧へ、なければフローを閉じる
                    if model.reservedCount > 0 {
                        model.screen = .pending
                    } else {
                        onClose(0)
                    }
                }
            case .pending:
                PendingListView(model: model, onClose: onClose)
            }
            if let adjustment = model.adjustments.first {
                CornerAdjustView(model: model, adjustment: adjustment)
                    .id(adjustment.id)
                    .transition(.opacity)
            }
        }
        .alert(
            "うまくいきませんでした",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - 撮影画面（A-3・A-4・O-3）

/// アプリ内カメラ（F1-1・F1-3 連続撮影・F1-8 上限）。撮影ガイド（枠と文言）を出す
struct CaptureView: View {
    @Bindable var model: CaptureViewModel
    let onClose: () -> Void
    @State private var photoItems: [PhotosPickerItem] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                if model.camera.authorization == .denied {
                    deniedContent
                } else {
                    // ファインダーは画面の幅いっぱいの 3:4（写真と同じ範囲。A-3 の 402×536）
                    viewfinder
                        .frame(width: geometry.size.width, height: geometry.size.width * 4 / 3)
                        .clipped()
                    bottomControls
                }
            }
        }
        .background(BookshelfStyle.cameraBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            if model.camera.authorization == .notDetermined {
                _ = await model.camera.requestAccess()
            }
            model.camera.start()
        }
        .onDisappear { model.camera.stop() }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importItems(items) }
        }
    }

    private var topBar: some View {
        ZStack {
            // 表紙の撮り直し（T9）では登録先を選ばない
            if model.purpose == .registration {
                DestinationMenu(shelves: model.selectableShelves(), destination: $model.destination, dark: true)
            } else {
                Text("表紙を撮り直す")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(.white)
            }
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(BookshelfStyle.cameraControl))
                }
                .accessibilityIdentifier("capture.close")
                .accessibilityLabel("閉じる")
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
    }

    // MARK: ファインダー

    private var viewfinder: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                preview
                if let quad = model.camera.liveQuad, !model.isAtLimit {
                    QuadOverlay(quad: quad, size: size)
                } else if !model.isAtLimit {
                    GuideFrame(size: size)
                }
                if model.isAtLimit && model.purpose == .registration {
                    limitOverlay
                } else if !model.isAtLimit {
                    VStack {
                        guideMessage
                            .padding(.top, 12)
                        Spacer()
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var preview: some View {
        #if DEBUG
            if let fake = model.camera as? FakeCameraSource {
                Image(uiImage: fake.preview)
                    .resizable()
                    .scaledToFill()
            } else if let camera = model.camera as? CameraController {
                CameraPreviewView(session: camera.box.session)
            }
        #else
            if let camera = model.camera as? CameraController {
                CameraPreviewView(session: camera.box.session)
            }
        #endif
    }

    /// 撮影ガイド（plan T5 ⑦・F1-2）。表紙を枠いっぱいに入れ、背景と分けると検出しやすい
    private var guideMessage: some View {
        VStack(spacing: 2) {
            Text("表紙全体が枠に入るように合わせてください")
                .font(BookshelfStyle.sans(13))
                .foregroundStyle(.white)
            Text("背景と色の違う所で撮ると、表紙を見つけやすくなります")
                .font(BookshelfStyle.sans(11))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.45)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.guide")
    }

    /// 30冊に達したとき（A-4）
    private var limitOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text("一度に登録できるのは30冊までです")
                    .font(BookshelfStyle.sans(16, .medium))
                    .foregroundStyle(.white)
                Text("いったん登録してから続けてください")
                    .font(BookshelfStyle.sans(13))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.limitMessage")
        }
    }

    // MARK: 下部

    private var bottomControls: some View {
        VStack(spacing: 0) {
            detectionPill
                .frame(height: 30)
                .padding(.top, 16)
            capturedStrip
                .frame(height: 52)
                .padding(.top, 18)
                .padding(.horizontal, 20)
            Spacer(minLength: 8)
            HStack {
                // 表紙の撮り直しは1枚撮れば終わるので、ライブラリと「完了」は出さない（場所だけ空ける）
                if model.purpose == .registration {
                    libraryButton
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
                Spacer()
                shutterButton
                Spacer()
                if model.purpose == .registration {
                    doneButton
                } else {
                    Color.clear.frame(width: 84, height: 48)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var detectionPill: some View {
        if model.camera.liveQuad != nil || model.showsDetectedFlash {
            Label("表紙を検出しました", systemImage: "checkmark")
                .font(BookshelfStyle.sans(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 30)
                .background(Capsule().fill(BookshelfStyle.cameraControl))
                .accessibilityIdentifier("capture.detected")
        }
    }

    private var capturedStrip: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(model.items.suffix(6)) { item in
                Group {
                    if let image = item.thumbnailImage {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Color.white.opacity(0.2)
                    }
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            if model.purpose == .registration {
                Text("\(model.reservedCount) / \(CaptureViewModel.limit)冊 撮影済み")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.leading, 6)
                    .accessibilityIdentifier("capture.count")
            }
            Spacer(minLength: 0)
        }
    }

    private var libraryButton: some View {
        PhotosPicker(
            selection: $photoItems, maxSelectionCount: max(model.remaining, 1), selectionBehavior: .ordered,
            matching: .images
        ) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 1.5))
        }
        .disabled(model.remaining == 0)
        .accessibilityIdentifier("capture.library")
        .accessibilityLabel("ライブラリから選ぶ")
        .accessibilityValue("残り\(model.remaining)冊まで選べます")
    }

    private var shutterButton: some View {
        Button {
            Task { await model.shutter() }
        } label: {
            ZStack {
                Circle().stroke(model.canShoot ? Color.white : Color.white.opacity(0.25), lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle().fill(model.canShoot ? Color.white : Color.white.opacity(0.18))
                    .frame(width: 60, height: 60)
            }
        }
        .disabled(!model.canShoot)
        .accessibilityIdentifier("capture.shutter")
        .accessibilityLabel("撮影")
    }

    private var doneButton: some View {
        Button {
            model.screen = .pending
        } label: {
            Text("完了")
                .font(BookshelfStyle.sans(15, .medium))
                .foregroundStyle(BookshelfStyle.ink)
                .frame(width: 76, height: 40)
                .background(Capsule().fill(Color.white))
                .padding(4)
                .overlay {
                    if model.isAtLimit {
                        Capsule().stroke(Color.white.opacity(0.6), lineWidth: 2)
                    }
                }
        }
        .accessibilityIdentifier("capture.done")
    }

    // MARK: カメラを許可しなかったとき（O-3）

    private var deniedContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "camera")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white)
                    .overlay {
                        Rectangle().fill(.white).frame(width: 2, height: 46).rotationEffect(.degrees(-45))
                    }
                Text("カメラへのアクセスがオフになっています")
                    .font(BookshelfStyle.sans(16, .medium))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                Text("設定アプリで local-bookshelf のカメラを\nオンにすると、表紙を撮影できます。")
                    .font(BookshelfStyle.sans(13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .background(Color(white: 0.11))
            .accessibilityIdentifier("capture.denied")
            Spacer()
            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("設定を開く")
                        .font(BookshelfStyle.sans(16, .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Color.white))
                }
                PhotosPicker(
                    selection: $photoItems, maxSelectionCount: max(model.remaining, 1), selectionBehavior: .ordered,
                    matching: .images
                ) {
                    Label("写真ライブラリから選ぶ", systemImage: "photo")
                        .font(BookshelfStyle.sans(15, .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(BookshelfStyle.cameraControl))
                }
                .disabled(model.remaining == 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func importItems(_ items: [PhotosPickerItem]) async {
        photoItems = []
        model.screen = .pending
        await model.importPhotos(items)
    }
}

/// ライブの検出結果（四隅）をファインダーの上に描く（A-3）
struct QuadOverlay: View {
    let quad: CoverQuad
    let size: CGSize

    var body: some View {
        let points = quad.points.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
        ZStack {
            Path { path in
                path.addLines(points)
                path.closeSubpath()
            }
            .stroke(Color.white, lineWidth: 1.5)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color.white).frame(width: 9, height: 9).position(points[i])
            }
        }
        .allowsHitTesting(false)
    }
}

/// 撮影ガイドの枠（表紙の形の四隅のかぎ）。表紙をこの枠いっぱいに入れる
struct GuideFrame: View {
    let size: CGSize

    var body: some View {
        let width = size.width * 0.72
        let height = min(width * 1.42, size.height * 0.82)
        let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2 + 14, width: width, height: height)
        let arm: CGFloat = 26
        Path { path in
            for corner in [
                (rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                (rect.maxX, rect.maxY, -1.0, -1.0), (rect.minX, rect.maxY, 1.0, -1.0),
            ] {
                let (x, y, dx, dy) = corner
                path.move(to: CGPoint(x: x + arm * dx, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + arm * dy))
            }
        }
        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("撮影ガイドの枠")
        .accessibilityIdentifier("capture.guideFrame")
    }
}
