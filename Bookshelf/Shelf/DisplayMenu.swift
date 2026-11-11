import SwiftUI

/// 閲覧画面の見え方（F6-6）
enum DisplayMode: Equatable {
    case shelf
    case grid
}

/// 下部バーの「表示」メニュー（G-2。F6-8）。見え方・まとめ方・この棚の並べ順・設定。
/// 見え方と「この棚の並べ順」（T7。F5-3）が動く。まとめ方（購入月別）は T13、設定は T8 で中身をつなぐ（今は押しても閉じるだけ）
struct DisplayMenu: View {
    let mode: DisplayMode
    /// 今の棚の並べ順（nil = 並べ順を出さない。買いたい本の棚は登録した順に並ぶため）
    var sortKey: ShelfSortKey?
    let onSelectMode: (DisplayMode) -> Void
    var onSelectSort: (ShelfSortKey) -> Void = { _ in }
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 暗転（表示メニューは 0.22。design-brief §2-1）
            Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255).opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityLabel("閉じる")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("menu.dismiss")
            VStack(alignment: .leading, spacing: 0) {
                section("見え方") {
                    item("棚", checked: mode == .shelf, id: "menu.mode.shelf") { onSelectMode(.shelf) }
                    item("グリッド", checked: mode == .grid, id: "menu.mode.grid") { onSelectMode(.grid) }
                }
                divider
                section("まとめ方") {
                    // 購入月別は T13
                    item("ジャンル別", checked: true, id: "menu.group.genre", action: onClose)
                    item("購入月別", checked: false, id: "menu.group.month", action: onClose)
                }
                if let sortKey {
                    divider
                    section("この棚の並べ順") {
                        ForEach(ShelfSortKey.allCases, id: \.self) { key in
                            item(key.label, checked: key == sortKey, id: "menu.sort.\(key.rawValue)") {
                                onSelectSort(key)
                            }
                        }
                    }
                }
                divider
                Button(action: onClose) {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .regular))
                        Text("設定")
                            .font(BookshelfStyle.sans(16))
                            .tracking(0.5)
                        Spacer()
                    }
                    .foregroundStyle(BookshelfStyle.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.settings")
            }
            .frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
            .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 10)
            .padding(.leading, 30)
            // 下部バー（高さ 48）の少し上に出す（Figma G-2: メニューの下端 y=772・バーの上端 y=790）
            .padding(.bottom, 68)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menu")
        }
        // 開いている間は VoiceOver で後ろの画面に移れないようにし、「閉じる」ジェスチャ（escape）でも閉じる（N-054・N5）
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    private var divider: some View {
        Rectangle()
            .fill(BookshelfStyle.line)
            .frame(height: 1)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(BookshelfStyle.sans(11))
                .tracking(1)
                .foregroundStyle(BookshelfStyle.faint)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.bottom, 4)
    }

    private func item(_ title: String, checked: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(BookshelfStyle.sans(16))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}
