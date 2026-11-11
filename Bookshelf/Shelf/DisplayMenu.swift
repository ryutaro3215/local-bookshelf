import SwiftUI

/// 閲覧画面の見え方（F6-6）
enum DisplayMode: Equatable {
    case shelf
    case grid
}

/// 下部バーの「表示」メニュー（G-2。F6-8）。見え方・まとめ方・この棚の並べ順・設定。
/// T6 で動くのは「見え方」だけ。まとめ方（購入月別）は T13、並べ順は T7、設定は T8 で中身をつなぐ（今は押しても閉じるだけ）
struct DisplayMenu: View {
    let mode: DisplayMode
    let onSelectMode: (DisplayMode) -> Void
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
                divider
                section("この棚の並べ順") {
                    // 並べ順の切り替えは T7
                    item("手動（自分で並べた順）", checked: true, id: "menu.sort.manual", action: onClose)
                    item("購入日が新しい順", checked: false, id: "menu.sort.purchased", action: onClose)
                    item("題名順", checked: false, id: "menu.sort.title", action: onClose)
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
