import SwiftUI
import UIKit

/// ジャンル名の入力のきまり（F-3 の「4/20」。保存するときは LibraryStore.sanitize で制御文字を除き前後の空白を落とす。S6）
enum GenreName {
    /// 画面で入力できる文字数（Figma F-3 の数え方。S6 の上限 200 より短い）
    static let maxLength = 20

    /// 入力中の文字を上限までに切り詰める（改行などの制御文字は入力の時点で除く）
    static func limit(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String(String.UnicodeScalarView(scalars)).prefix(maxLength))
    }

    /// 保存できる名前か（整えたあとに空でない）
    static func isValid(_ text: String) -> Bool {
        !LibraryStore.sanitize(text).isEmpty
    }
}

// MARK: - ジャンルの追加（F-3）

/// ジャンルの追加（F-3）。名前と置き場所（区分）を選ぶ。区分の初期値はマイジャンル。選んだ区分の末尾に追加する
struct GenreAddView: View {
    let categories: [GenreCategory]
    let onCancel: () -> Void
    let onAdd: (String, String) -> Void
    @State private var name = ""
    @State private var categoryID = InitialGenres.myGenres.id

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("ジャンルを追加")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("genreAdd.title")
                HStack {
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(BookshelfStyle.sans(15))
                            .foregroundStyle(BookshelfStyle.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("genreAdd.cancel")
                    Spacer()
                    Button {
                        onAdd(GenreName.limit(name), categoryID)
                    } label: {
                        Text("追加")
                            .font(BookshelfStyle.sans(15, .medium))
                            .foregroundStyle(GenreName.isValid(name) ? BookshelfStyle.ink : BookshelfStyle.faint)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!GenreName.isValid(name))
                    .accessibilityIdentifier("genreAdd.save")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    fieldLabel("名前")
                    HStack(spacing: 8) {
                        LimitedTextField(
                            text: $name, size: 17, accessibilityLabel: "名前", identifier: "genreAdd.name",
                            onReturn: {})
                        Text("\(name.count)/\(GenreName.maxLength)")
                            .font(BookshelfStyle.sans(11))
                            .foregroundStyle(BookshelfStyle.faint)
                            .accessibilityIdentifier("genreAdd.counter")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14).stroke(BookshelfStyle.ink, lineWidth: 1.5)
                    )
                    Text("好きな作家やシリーズの棚も作れます")
                        .font(BookshelfStyle.sans(12))
                        .tracking(0.3)
                        .foregroundStyle(BookshelfStyle.faint)
                        .padding(.top, 10)
                    fieldLabel("置き場所（区分）")
                        .padding(.top, 22)
                    VStack(spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                            categoryRow(category, isLast: index == categories.count - 1)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
                    Text("選んだ区分の末尾に追加。本を入れると本棚に表示されます")
                        .font(BookshelfStyle.sans(12))
                        .tracking(0.3)
                        .foregroundStyle(BookshelfStyle.faint)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.white)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(BookshelfStyle.sans(13, .medium))
            .tracking(0.5)
            .foregroundStyle(BookshelfStyle.ink)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func categoryRow(_ category: GenreCategory, isLast: Bool) -> some View {
        let selected = category.id == categoryID
        return Button {
            categoryID = category.id
        } label: {
            HStack {
                Text(category.name)
                    .font(BookshelfStyle.sans(16, selected ? .medium : .regular))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { CardSeparator() }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("genreAdd.category.\(category.id)")
    }
}

// MARK: - 名前の変更（F-4b）

/// ジャンル名の変更のダイアログ（F-4b。白・角 18・幅 290。キャンセル／保存）
struct GenreRenameDialog: View {
    let currentName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void
    @State private var name: String

    init(currentName: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    var body: some View {
        GenreDialog(
            onCancel: onCancel,
            confirmTitle: "保存", confirmID: "rename.save", isDestructive: false,
            isConfirmEnabled: GenreName.isValid(name), onConfirm: { onSave(GenreName.limit(name)) },
            cancelID: "rename.cancel", dialogID: "rename.dialog"
        ) {
            VStack(spacing: 8) {
                Text("ジャンル名を変更")
                    .font(BookshelfStyle.sans(17, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityIdentifier("rename.title")
                Text("「\(currentName)」の新しい名前")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(BookshelfStyle.sub)
                LimitedTextField(
                    text: $name, size: 16, accessibilityLabel: "新しい名前", identifier: "rename.field",
                    onReturn: { if GenreName.isValid(name) { onSave(GenreName.limit(name)) } }
                )
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12).stroke(BookshelfStyle.ink, lineWidth: 1.5))
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - 削除の確認（F-5）

/// ジャンルの削除の確認（F-5）。中の本は未分類へ移り、本は消えない（F4-1）
struct GenreDeleteDialog: View {
    let name: String
    /// 中の本の冊数（購入済み・買いたいの両方。どちらも未分類へ移る）
    let bookCount: Int
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GenreDialog(
            onCancel: onCancel,
            confirmTitle: "削除", confirmID: "genreDelete.confirm", isDestructive: true,
            isConfirmEnabled: true, onConfirm: onDelete,
            cancelID: "genreDelete.cancel", dialogID: "genreDelete.dialog"
        ) {
            VStack(spacing: 10) {
                Text("「\(name)」を削除しますか？")
                    .font(BookshelfStyle.sans(17, .medium))
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityIdentifier("genreDelete.title")
                Text(message)
                    .font(BookshelfStyle.sans(13))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BookshelfStyle.sub)
                    .accessibilityIdentifier("genreDelete.message")
            }
        }
    }

    private var message: String {
        bookCount > 0 ? "中の\(bookCount)冊は未分類に移動します。\n本は削除されません。" : "このジャンルに本は入っていません。"
    }
}

/// 設定のダイアログの共通の形（design-brief §3: 白・角 18・幅 290。下に横並びのボタン 48・区切り線 #E4E4E4）
struct GenreDialog<Content: View>: View {
    let onCancel: () -> Void
    let confirmTitle: String
    let confirmID: String
    let isDestructive: Bool
    let isConfirmEnabled: Bool
    let onConfirm: () -> Void
    let cancelID: String
    let dialogID: String
    @ViewBuilder let content: () -> Content

    private let divider = Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255)

    var body: some View {
        ZStack {
            Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255).opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    .padding(.bottom, 22)
                Rectangle().fill(divider).frame(height: 1)
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(BookshelfStyle.sans(16))
                            .foregroundStyle(BookshelfStyle.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(cancelID)
                    Rectangle().fill(divider).frame(width: 1)
                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(BookshelfStyle.sans(16, isDestructive ? .bold : .medium))
                            .foregroundStyle(
                                isDestructive
                                    ? BookshelfStyle.danger
                                    : (isConfirmEnabled ? BookshelfStyle.ink : BookshelfStyle.faint)
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isConfirmEnabled)
                    .accessibilityIdentifier(confirmID)
                }
                .frame(height: 48)
            }
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier(dialogID)
        }
        .accessibilityAction(.escape, onCancel)
    }
}

// MARK: - 文字数の上限つきの入力欄

/// ジャンル名の入力欄（Noto Serif JP 600）。かな漢字変換の確定後に上限（20文字）を超えた分を切る。
/// SwiftUI の TextField は、束ねた値を切り詰めても表示中の文字が残ることがあるため、UITextField で作る。
/// 表示されたらすぐ入力できるようにする（F-3・F-4b はキーボードを出した状態）
struct LimitedTextField: UIViewRepresentable {
    @Binding var text: String
    let size: CGFloat
    let accessibilityLabel: String
    let identifier: String
    let onReturn: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = text
        field.font = Self.font(size: size)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
        field.returnKeyType = .done
        field.clearButtonMode = .never
        field.accessibilityLabel = accessibilityLabel
        field.accessibilityIdentifier = identifier
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        DispatchQueue.main.async {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.markedTextRange == nil, field.text != text {
            field.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Noto Serif JP 600（Dynamic Type に合わせて大きさが変わる）
    static func font(size: CGFloat) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Noto Serif JP",
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold],
        ])
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LimitedTextField

        init(parent: LimitedTextField) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            // 変換中（下線つきの未確定の文字）は切らない。確定したら上限までに切る
            guard field.markedTextRange == nil else { return }
            let limited = GenreName.limit(field.text ?? "")
            if field.text != limited {
                field.text = limited
            }
            parent.text = limited
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            textField.resignFirstResponder()
            return true
        }
    }
}
