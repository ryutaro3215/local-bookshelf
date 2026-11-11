import SwiftData
import SwiftUI

/// 設定（F-1。F4-0）。閲覧画面の「表示」メニューの一番下から入る。
/// 本棚（ジャンル管理）・プライバシー（通信なし）・このアプリについて（バージョン・ライセンス）
struct SettingsView: View {
    let store: LibraryStore
    @Query private var shelves: [Shelf]
    @Environment(\.dismiss) private var dismiss
    @State private var showsGenres = false
    @State private var showsLicense = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader(backTitle: "本棚", backID: "settings.back", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LargeTitle(text: "設定", id: "settings.title")
                    SectionLabel(text: "本棚")
                        .padding(.top, 16)
                    Button {
                        showsGenres = true
                    } label: {
                        SettingsRow(title: "ジャンル管理", value: "\(genreCount)件", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("ジャンル管理")
                    .accessibilityValue("\(genreCount)件")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("settings.genres")
                    Footnote(text: "ジャンル（棚）の追加・名前の変更・並び替え・削除")
                    SectionLabel(text: "プライバシー")
                        .padding(.top, 26)
                    privacyCard
                    SectionLabel(text: "このアプリについて")
                        .padding(.top, 42)
                    VStack(spacing: 0) {
                        SettingsRow(title: "バージョン", value: version, showsChevron: false)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("settings.version")
                        CardSeparator()
                        Button {
                            showsLicense = true
                        } label: {
                            SettingsRow(title: "ライセンス", value: nil, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.license")
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showsGenres) {
            ShelfListView(store: store)
        }
        .navigationDestination(isPresented: $showsLicense) {
            LicenseView()
        }
    }

    /// ジャンルの数（買いたい本・未分類は数えない。Figma F-1「29件」＝初期28＋マイジャンル1）
    private var genreCount: Int {
        shelves.filter { !$0.isSystem }.count
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BookshelfStyle.ink)
                Text("通信なし・データは端末内のみ")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
            }
            Text("このアプリはインターネットに接続しません。\nアカウント登録もありません。表紙の写真と本の\nデータは、この iPhone の中だけに保存されます。")
                .font(BookshelfStyle.sans(13))
                .tracking(0.3)
                .lineSpacing(5)
                .foregroundStyle(BookshelfStyle.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.privacy")
    }
}

/// 設定の1行（項目名・右に値と ›）
private struct SettingsRow: View {
    let title: String
    let value: String?
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(BookshelfStyle.sans(16))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(BookshelfStyle.sans(13))
                    .foregroundStyle(BookshelfStyle.sub)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BookshelfStyle.faint)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// ライセンス（設定の「このアプリについて」）。同梱の書体のライセンスを示す。
/// Figma に画面が無いため最小限の一覧にした。ライセンス文そのものの同梱は N-033 で決める
struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader(backTitle: "設定", backID: "license.back", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LargeTitle(text: "ライセンス", id: "license.title")
                    SectionLabel(text: "書体")
                        .padding(.top, 22)
                    VStack(spacing: 0) {
                        entry("Noto Sans JP")
                        CardSeparator()
                        entry("Noto Serif JP")
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
                    Footnote(text: "どちらも SIL Open Font License, Version 1.1 で提供されています。")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func entry(_ name: String) -> some View {
        HStack {
            Text(name)
                .font(BookshelfStyle.sans(16))
                .foregroundStyle(BookshelfStyle.ink)
            Spacer()
            Text("SIL OFL 1.1")
                .font(BookshelfStyle.sans(13))
                .foregroundStyle(BookshelfStyle.sub)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 設定・ジャンル管理で使う部品

/// 上の行（左に「‹ 戻る先」、右に任意のボタン。中央に小さな見出しを出せる。F-1・F-2a・F-2b）
struct NavigationHeader<Trailing: View>: View {
    let backTitle: String?
    let backID: String
    var onBack: () -> Void = {}
    /// スクロールして大きな見出しが隠れたときに中央に出す見出し（F-2b）
    var inlineTitle: String?
    /// 下に区切り線を引く（スクロールしたとき）
    var showsDivider = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            if let inlineTitle {
                Text(inlineTitle)
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 90)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack {
                if let backTitle {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .regular))
                            Text(backTitle)
                                .font(BookshelfStyle.sans(15))
                                .lineLimit(1)
                        }
                        .foregroundStyle(BookshelfStyle.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(backTitle)に戻る")
                    .accessibilityIdentifier(backID)
                }
                Spacer()
                trailing()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BookshelfStyle.line)
                .frame(height: 1)
                .opacity(showsDivider ? 1 : 0)
        }
    }
}

extension NavigationHeader where Trailing == EmptyView {
    init(backTitle: String?, backID: String, onBack: @escaping () -> Void) {
        self.init(backTitle: backTitle, backID: backID, onBack: onBack, trailing: { EmptyView() })
    }
}

/// 大きな見出し（Sans 500・26。design-brief §2-2）
struct LargeTitle: View {
    let text: String
    let id: String

    var body: some View {
        Text(text)
            .font(BookshelfStyle.sans(26, .medium, relativeTo: .largeTitle))
            .tracking(0.5)
            .foregroundStyle(BookshelfStyle.ink)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
    }
}

/// カードの上の小さな見出し（区分の見出しと同じ: Sans 500・11・FAINT・字間 1）
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BookshelfStyle.sans(11, .medium))
            .tracking(1)
            .foregroundStyle(BookshelfStyle.faint)
            .padding(.leading, 16)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// カードの下の補足（Sans 12・FAINT）
struct Footnote: View {
    let text: String
    var color: Color = BookshelfStyle.faint

    var body: some View {
        Text(text)
            .font(BookshelfStyle.sans(12))
            .lineSpacing(5)
            .foregroundStyle(color)
            .padding(.leading, 16)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// カードの中の区切り線（左 16 を空ける。design-brief §3）
struct CardSeparator: View {
    var body: some View {
        Rectangle()
            .fill(BookshelfStyle.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}
