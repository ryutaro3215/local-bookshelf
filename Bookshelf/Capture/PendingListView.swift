import PhotosUI
import SwiftUI
import os

/// 登録待ちの一覧（C-2・C-5・C-6）。題名・ジャンル・購入済みのチェックを確かめて登録する（F2-1・F3-4・F1-8）
struct PendingListView: View {
    @Bindable var model: CaptureViewModel
    let onClose: (_ registered: Int) -> Void
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var confirmClose = false
    @State private var isPickingPhotos = false
    @FocusState private var focusedItem: UUID?
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "PendingList")

    var body: some View {
        VStack(spacing: 0) {
            header
            addButtons
                .padding(.horizontal, 20)
                .padding(.top, 14)
            ownedHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
            // 行を左へスワイプして「外す」と、登録待ちから外れて残りの冊数が戻る（Figma に削除の形が無いため iOS 標準の操作）
            let shelves = model.selectableShelves()
            List {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    PendingRow(item: item, index: index, shelves: shelves, focusedItem: $focusedItem)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("外す", role: .destructive) { model.remove(item) }
                                .accessibilityIdentifier("pending.row.\(index).remove")
                        }
                        .accessibilityAction(named: "登録待ちから外す") { model.remove(item) }
                }
                if model.processingCount > 0 {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("表紙を補正しています…")
                            .font(BookshelfStyle.sans(13))
                            .foregroundStyle(BookshelfStyle.sub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("pending.processing")
                }
            }
            .listStyle(.plain)
            .contentMargins(.vertical, 12, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        // 選べる枚数は登録待ちの残りまで（F1-8）
        .photosPicker(
            isPresented: $isPickingPhotos, selection: $photoItems, maxSelectionCount: max(model.remaining, 1),
            selectionBehavior: .ordered, matching: .images
        )
        .onAppear {
            if model.opensLibraryOnAppear {
                model.opensLibraryOnAppear = false
                isPickingPhotos = true
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                photoItems = []
                await model.importPhotos(items)
            }
        }
        .confirmationDialog(
            "登録せずに閉じますか？", isPresented: $confirmClose, titleVisibility: .visible
        ) {
            Button("登録せずに閉じる", role: .destructive) { onClose(0) }
            Button("一覧に戻る", role: .cancel) {}
        } message: {
            Text("登録待ちの\(model.reservedCount)冊は保存されません")
        }
    }

    // MARK: 上部

    private var header: some View {
        ZStack {
            Text("登録待ち \(model.reservedCount) / \(CaptureViewModel.limit)冊")
                .font(BookshelfStyle.sans(16, .medium))
                .foregroundStyle(BookshelfStyle.ink)
                .accessibilityIdentifier("pending.heading")
            HStack {
                Button("閉じる") {
                    if model.reservedCount > 0 {
                        confirmClose = true
                    } else {
                        onClose(0)
                    }
                }
                .font(BookshelfStyle.sans(15))
                .foregroundStyle(BookshelfStyle.ink)
                .accessibilityIdentifier("pending.close")
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
    }

    private var addButtons: some View {
        HStack(spacing: 12) {
            Button {
                model.screen = .camera
            } label: {
                Label("撮影を追加", systemImage: "camera")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(BookshelfStyle.fill))
            }
            .disabled(model.remaining == 0)
            .accessibilityIdentifier("pending.addCamera")
            Button {
                isPickingPhotos = true
            } label: {
                Label("ライブラリから追加", systemImage: "photo")
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(BookshelfStyle.fill))
            }
            .disabled(model.remaining == 0)
            .accessibilityIdentifier("pending.addLibrary")
            .accessibilityValue("残り\(model.remaining)冊まで選べます")
        }
        .opacity(model.remaining == 0 ? 0.45 : 1)
    }

    private var ownedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("購入済み \(model.ownedCount) / \(model.items.count)冊")
                    .font(BookshelfStyle.sans(14, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityIdentifier("pending.ownedCount")
                Spacer()
                smallButton("すべて選択", id: "pending.selectAll", disabled: model.ownedCount == model.items.count) {
                    model.setAllOwned(true)
                }
                smallButton("すべて解除", id: "pending.deselectAll", disabled: model.ownedCount == 0) {
                    model.setAllOwned(false)
                }
            }
            Text("チェックあり＝購入済み　チェックなし＝買いたい本")
                .font(BookshelfStyle.sans(11))
                .foregroundStyle(BookshelfStyle.faint)
        }
    }

    private func smallButton(_ title: String, id: String, disabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Text(title)
                .font(BookshelfStyle.sans(13))
                .foregroundStyle(disabled ? BookshelfStyle.faint : BookshelfStyle.ink)
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(Capsule().fill(BookshelfStyle.fill))
        }
        .disabled(disabled)
        .accessibilityIdentifier(id)
    }

    // MARK: 下部

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(BookshelfStyle.panelLine).frame(height: 1)
            Group {
                if model.untitledCount > 0 {
                    untitledNotice
                } else {
                    Text("購入済み \(model.ownedCount)冊・買いたい本 \(model.wantedCount)冊")
                        .font(BookshelfStyle.sans(12))
                        .foregroundStyle(BookshelfStyle.sub)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("pending.summary")
                }
            }
            .frame(minHeight: 50)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Button(action: register) {
                Text(model.untitledCount > 0 ? "題名を入力すると登録できます" : "\(model.items.count)冊を登録")
                    .font(BookshelfStyle.sans(16, .medium))
                    .foregroundStyle(model.canRegister ? Color.white : BookshelfStyle.faint)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(model.canRegister ? BookshelfStyle.ink : BookshelfStyle.fill))
            }
            .disabled(!model.canRegister)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .accessibilityIdentifier("pending.register")
        }
    }

    private var untitledNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("題名が未入力の本が\(model.untitledCount)冊あります", systemImage: "exclamationmark.circle")
                    .font(BookshelfStyle.sans(13, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityIdentifier("pending.untitledNotice")
                Spacer()
                Button {
                    focusedItem = model.items.first(where: { !$0.hasTitle })?.id
                } label: {
                    HStack(spacing: 4) {
                        Text("順に入力する")
                        Image(systemName: "chevron.right")
                    }
                    .font(BookshelfStyle.sans(13, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                }
                .accessibilityIdentifier("pending.fillNext")
            }
            if model.recognizingUntitledCount > 0 {
                Text("うち\(model.recognizingUntitledCount)冊は読み取り中。候補が届くと自動で入ります")
                    .font(BookshelfStyle.sans(11))
                    .foregroundStyle(BookshelfStyle.sub)
                    .padding(.leading, 20)
            }
        }
    }

    private func register() {
        do {
            let count = try model.register()
            onClose(count)
        } catch {
            Self.logger.error("登録に失敗: \(error.localizedDescription, privacy: .public)")
            model.errorMessage = "登録できませんでした。もう一度お試しください"
        }
    }
}

/// 登録待ちの1行（チェック・表紙・題名・ジャンル・所持状況）
struct PendingRow: View {
    @Bindable var item: PendingBook
    let index: Int
    let shelves: [Shelf]
    var focusedItem: FocusState<UUID?>.Binding

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                item.owned.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.owned ? BookshelfStyle.ink : Color.white)
                    .overlay {
                        if item.owned {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            RoundedRectangle(cornerRadius: 6).stroke(BookshelfStyle.checkOff, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pending.row.\(index).check")
            .accessibilityLabel("購入済み")
            .accessibilityValue(item.owned ? "オン" : "オフ")
            .accessibilityAddTraits(item.owned ? .isSelected : [])

            Group {
                if let image = item.thumbnailImage {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    BookshelfStyle.fill
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 8) {
                titleField
                HStack(spacing: 10) {
                    genreMenu
                    status
                }
            }
        }
    }

    @ViewBuilder
    private var titleField: some View {
        let missing = !item.hasTitle && !item.isRecognizing
        ZStack(alignment: .leading) {
            if item.isRecognizing && !item.hasTitle {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("題名を読み取り中…")
                        .font(BookshelfStyle.serif(15))
                        .foregroundStyle(BookshelfStyle.faint)
                }
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
            }
            TextField(
                "",
                text: Binding(
                    get: { item.title },
                    set: { newValue in
                        item.title = newValue
                        item.titleEdited = true
                    }),
                prompt: item.isRecognizing ? nil : Text("題名を入力").foregroundStyle(BookshelfStyle.faint)
            )
            .font(BookshelfStyle.serif(16))
            .foregroundStyle(BookshelfStyle.ink)
            .focused(focusedItem, equals: item.id)
            .submitLabel(.next)
            .padding(.leading, 12)
            .padding(.trailing, missing ? 44 : 12)
            .accessibilityIdentifier("pending.row.\(index).title")
            if missing {
                HStack {
                    Spacer()
                    Text("必須")
                        .font(BookshelfStyle.sans(11, .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                        .padding(.trailing, 12)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: 36)
        .background {
            if missing {
                RoundedRectangle(cornerRadius: 10).stroke(BookshelfStyle.ink, lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(BookshelfStyle.fill)
            }
        }
    }

    private var genreMenu: some View {
        Menu {
            ForEach(shelves) { shelf in
                Button(shelf.name) { item.shelf = shelf }
            }
        } label: {
            HStack(spacing: 6) {
                Text(item.shelf.name)
                    .font(BookshelfStyle.serif(11))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(BookshelfStyle.ink)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(BookshelfStyle.fill))
        }
        .accessibilityIdentifier("pending.row.\(index).genre")
        .accessibilityValue(item.shelf.name)
    }

    @ViewBuilder
    private var status: some View {
        if !item.hasTitle && !item.isRecognizing {
            Label("題名を入力してください", systemImage: "exclamationmark.circle")
                .font(BookshelfStyle.sans(11, .medium))
                .foregroundStyle(BookshelfStyle.ink)
        } else {
            Text(item.owned ? "購入済み（購入日 今日）" : "買いたい本へ")
                .font(BookshelfStyle.sans(11))
                .foregroundStyle(BookshelfStyle.sub)
                .accessibilityIdentifier("pending.row.\(index).status")
        }
    }
}
