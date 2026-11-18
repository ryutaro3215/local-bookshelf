import SwiftUI
import UIKit

/// 共有画像の型（Figma の共有画像の行 `61:33720` ほか。design-brief §7）。
/// ShareLayoutEngine が決めた配置のとおりに、1080 幅の画素で描く（ImageRenderer で画像にする）。
/// ベージュの地に表紙を格子に並べ、表紙の下に題名、右端に縦書きの区分名、左下に事実、右下にアプリ名。41冊〜はモザイクと大きな数字
struct ShareTemplateView: View {
    let layout: ShareLayout
    let covers: [UUID: UIImage]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShareFonts.background
            ForEach(Array(layout.bands.enumerated()), id: \.offset) { _, band in
                Rectangle()
                    .fill(ShareFonts.band)
                    .frame(width: band.width, height: band.height)
                    .offset(x: band.minX, y: band.minY)
            }
            if let number = layout.bigNumber {
                header(number: number, heading: layout.heading ?? "")
            }
            ForEach(layout.covers, id: \.id) { placed in
                cover(placed)
                if !placed.titleLines.isEmpty {
                    title(placed)
                }
            }
            ForEach(Array(layout.labels.enumerated()), id: \.offset) { _, label in
                sectionLabel(label)
            }
            footer
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    // MARK: - 表紙・題名

    @ViewBuilder
    private func cover(_ placed: PlacedCover) -> some View {
        let frame = placed.frame
        let mosaic = layout.style == .mosaic
        Group {
            if let image = covers[placed.id] {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    // 表紙は切り抜かない（縦横比はレイアウトで合わせてある）
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(ShareFonts.band)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: mosaic ? 0 : 3))
        // 柔らかい影（モザイクは隙間なく詰めるので影を付けない）
        .shadow(color: .black.opacity(mosaic ? 0 : 0.16), radius: mosaic ? 0 : 12, x: 0, y: mosaic ? 0 : 8)
        .offset(x: frame.minX, y: frame.minY)
    }

    private func title(_ placed: PlacedCover) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(placed.titleLines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(ShareFonts.serif(placed.titleSize))
                    .tracking(placed.titleSize * 0.02)
                    .foregroundStyle(ShareFonts.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: placed.titleSize * 1.32)
            }
        }
        .frame(width: placed.titleFrame.width)
        .offset(x: placed.titleFrame.minX, y: placed.titleFrame.minY)
    }

    // MARK: - 右端の区分名（縦書き）

    @ViewBuilder
    private func sectionLabel(_ label: PlacedLabel) -> some View {
        let frame = label.frame
        Group {
            if label.rotated {
                // 日付・英語名は90度回して上から読む
                Text(verbatim: label.text)
                    .font(ShareFonts.serif(label.size, .semibold))
                    .tracking(label.size * 0.08)
                    .foregroundStyle(ShareFonts.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: max(frame.height - 20, 60))
                    .fixedSize(horizontal: false, vertical: true)
                    .rotationEffect(.degrees(90))
            } else {
                VStack(spacing: label.size * 0.08) {
                    ForEach(
                        Array(verticalCharacters(label.text, size: label.size, height: frame.height).enumerated()),
                        id: \.offset
                    ) {
                        _, character in
                        Text(verbatim: character)
                            .font(ShareFonts.serif(label.size, .semibold))
                            .foregroundStyle(ShareFonts.accent)
                            .frame(height: label.size)
                    }
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }

    /// 縦に積む文字。帯に収まらない分は「︙」にする
    private func verticalCharacters(_ text: String, size: CGFloat, height: CGFloat) -> [String] {
        let characters = text.map { $0 == "ー" ? "丨" : String($0) }
        let fits = max(Int((height - 20) / (size * 1.08)), 1)
        guard characters.count > fits else { return characters }
        return Array(characters.prefix(max(fits - 1, 0))) + ["︙"]
    }

    // MARK: - モザイクの大きな数字と見出し

    private func header(number: String, heading: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 18) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(verbatim: number)
                    .font(ShareFonts.serif(190))
                    .foregroundStyle(ShareFonts.text)
                Text("冊")
                    .font(ShareFonts.serif(60))
                    .foregroundStyle(ShareFonts.text)
            }
            Text(verbatim: heading)
                .font(ShareFonts.serif(50))
                .foregroundStyle(ShareFonts.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: layout.size.width - 120, height: 230, alignment: .bottomLeading)
        .offset(x: 60, y: layout.headerTop)
    }

    // MARK: - 下（事実・アプリ名）

    private var footer: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(verbatim: layout.fact)
                .font(ShareFonts.sans(28))
                .tracking(0.5)
                .foregroundStyle(ShareFonts.note)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 24)
            Text(verbatim: layout.appName)
                .font(ShareFonts.serif(36, .semibold))
                .tracking(0.5)
                .foregroundStyle(ShareFonts.accent)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: layout.size.width - 112, height: 60)
        .offset(x: 56, y: layout.footerY - 30)
    }
}
