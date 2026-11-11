import SwiftUI

/// 四隅の手動調整（N-1・N-2。requirements F1-2 の後半）。
/// 自動検出に失敗した1枚を出し、画像の各辺から約10%内側に置いた四隅のハンドルを、表紙のふちまでドラッグしてもらう。
/// ドラッグ中はルーペで指の下を拡大して見せる
struct CornerAdjustView: View {
    @Bindable var model: CaptureViewModel
    let adjustment: ManualAdjustment

    /// 初期の四隅を画像の各辺から内側に置く割合（plan T5 ⑧）
    static let initialInset: CGFloat = 0.1

    /// 正規化座標（Vision と同じく原点は左下）
    @State private var quad = CoverQuad.inset(CornerAdjustView.initialInset)
    @State private var dragging: Corner?
    @State private var isConfirming = false

    enum Corner: Int, CaseIterable, Identifiable {
        case topLeft, topRight, bottomRight, bottomLeft
        var id: Int { rawValue }
        var name: String {
            switch self {
            case .topLeft: "topLeft"
            case .topRight: "topRight"
            case .bottomRight: "bottomRight"
            case .bottomLeft: "bottomLeft"
            }
        }
        var label: String {
            switch self {
            case .topLeft: "左上の角"
            case .topRight: "右上の角"
            case .bottomRight: "右下の角"
            case .bottomLeft: "左下の角"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                let frame = imageFrame(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: adjustment.preview)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .accessibilityIdentifier("adjust.image")
                    outline(in: frame)
                    ForEach(Corner.allCases) { corner in
                        handle(corner, in: frame)
                    }
                    if let dragging {
                        loupe(for: dragging, in: frame, container: geometry.size)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipped()
            message
                .padding(.horizontal, 46)
                .padding(.top, 20)
            Spacer(minLength: 16)
            buttons
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(BookshelfStyle.cameraBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        ZStack {
            if model.purpose == .registration {
                DestinationMenu(shelves: model.selectableShelves(), destination: $model.destination, dark: true)
            }
            HStack {
                Button {
                    model.discardAdjustment(adjustment)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(BookshelfStyle.cameraControl))
                }
                .accessibilityLabel("この写真を使わない")
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
    }

    private var message: some View {
        Group {
            if dragging != nil {
                Text("ルーペを見ながら、角を表紙のふちに合わせます")
            } else {
                Text("表紙の四隅を見つけられませんでした\n角を動かして、表紙のふちに合わせてください")
            }
        }
        .font(BookshelfStyle.sans(13))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .lineSpacing(6)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
        .accessibilityIdentifier("adjust.message")
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                model.discardAdjustment(adjustment)
            } label: {
                Text("撮り直す")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(BookshelfStyle.cameraControl))
            }
            .accessibilityIdentifier("adjust.retake")
            Button {
                isConfirming = true
                Task {
                    await model.confirmAdjustment(adjustment, corners: quad)
                    isConfirming = false
                }
            } label: {
                Text("この範囲で使う")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Color.white))
            }
            .disabled(isConfirming)
            .accessibilityIdentifier("adjust.confirm")
        }
    }

    // MARK: - 四隅

    /// 画像を枠の中に縦横比を保って収めた位置
    private func imageFrame(in container: CGSize) -> CGRect {
        let image = adjustment.preview.size
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width,
            height: size.height)
    }

    private func point(_ corner: Corner) -> CGPoint {
        quad.points[corner.rawValue]
    }

    /// 正規化座標（原点は左下）→ 画面の座標
    private func viewPoint(_ p: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + (1 - p.y) * frame.height)
    }

    private func setPoint(_ corner: Corner, viewLocation: CGPoint, in frame: CGRect) {
        let x = min(max((viewLocation.x - frame.minX) / frame.width, 0), 1)
        let y = min(max(1 - (viewLocation.y - frame.minY) / frame.height, 0), 1)
        let p = CGPoint(x: x, y: y)
        switch corner {
        case .topLeft: quad.topLeft = p
        case .topRight: quad.topRight = p
        case .bottomRight: quad.bottomRight = p
        case .bottomLeft: quad.bottomLeft = p
        }
    }

    private func outline(in frame: CGRect) -> some View {
        Path { path in
            path.addLines(quad.points.map { viewPoint($0, in: frame) })
            path.closeSubpath()
        }
        .stroke(Color.white, lineWidth: 1.5)
        .allowsHitTesting(false)
    }

    private func handle(_ corner: Corner, in frame: CGRect) -> some View {
        let position = viewPoint(point(corner), in: frame)
        return Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 22, height: 22)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        dragging = corner
                        setPoint(corner, viewLocation: value.location, in: frame)
                    }
                    .onEnded { _ in dragging = nil }
            )
            .accessibilityElement()
            .accessibilityIdentifier("adjust.handle.\(corner.name)")
            .accessibilityLabel(corner.label)
            .accessibilityAddTraits(.isButton)
    }

    /// ルーペ（N-2）: 指の下を2倍に拡大して、指から離れた位置に出す
    private func loupe(for corner: Corner, in frame: CGRect, container: CGSize) -> some View {
        let diameter: CGFloat = 92
        let zoom: CGFloat = 2
        let center = viewPoint(point(corner), in: frame)
        // 指で隠れないよう、角の上（上端に近ければ下）に出す
        let above = center.y - diameter * 1.1
        let loupeCenter = CGPoint(
            x: min(max(center.x, diameter / 2), container.width - diameter / 2),
            y: above > diameter / 2 ? above : center.y + diameter * 1.1)
        return ZStack {
            Image(uiImage: adjustment.preview)
                .resizable()
                .frame(width: frame.width * zoom, height: frame.height * zoom)
                .offset(
                    x: diameter / 2 - (center.x - frame.minX) * zoom,
                    y: diameter / 2 - (center.y - frame.minY) * zoom
                )
                .frame(width: diameter, height: diameter, alignment: .topLeading)
                .clipShape(Circle())
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(.white)
            Circle().stroke(Color.white, lineWidth: 2)
        }
        .frame(width: diameter, height: diameter)
        .position(loupeCenter)
        .allowsHitTesting(false)
    }
}
