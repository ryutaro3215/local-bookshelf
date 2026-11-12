import SwiftData
import SwiftUI
import os

/// 本を編集（E-6 購入済み・E-7 買いたい本。requirements F6-4・§10.3・F2-1〜F2-3）。
/// 詳細ページの「編集」から全画面で出す。「完了」で保存（LibraryStore.updateBook → commit。失敗したら rollback）、
/// 「キャンセル」で破棄する。項目と並びは所持状況にかかわらず同じ（題名・ジャンル・所持状況・購入日。表紙の撮り直し）
struct BookEditView: View {
    let book: Book
    let environment: AppEnvironment
    /// 保存できた（新しい表紙に入れ替えたかを渡す）
    let onSaved: (_ coverReplaced: Bool) -> Void
    let onCancel: () -> Void

    @State private var title: String
    /// ジャンル（通常は必ずある。無いときは未分類として保存する）
    @State private var shelf: Shelf?
    @State private var ownership: Ownership
    @State private var purchaseDate: Date
    /// 題名の候補の読み取り（表紙を撮り直したら前の読み取りを取り消す。N-071）
    @State private var recognition = TitleCandidateLoader()
    @State private var cover: UIImage?
    /// 撮り直した表紙（保存するまでファイルには書かない）
    @State private var newCover: ProcessedCover?
    @State private var reshoot: CaptureViewModel?
    @State private var showsGenrePicker = false
    @State private var showsDatePicker = false
    @State private var errorMessage: String?
    /// データは保存できたが表紙を入れ替えられなかった（OK で閉じる）
    @State private var closesAfterError = false
    @FocusState private var titleFocused: Bool

    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "BookEdit")

    init(
        book: Book, environment: AppEnvironment, onSaved: @escaping (_ coverReplaced: Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.book = book
        self.environment = environment
        self.onSaved = onSaved
        self.onCancel = onCancel
        _title = State(initialValue: book.title)
        _shelf = State(initialValue: book.shelf)
        _ownership = State(initialValue: book.ownership)
        _purchaseDate = State(initialValue: book.purchaseDate ?? Calendar.current.startOfDay(for: .now))
    }

    private var store: LibraryStore { environment.store }
    private var canSave: Bool { !LibraryStore.sanitize(title).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    coverView
                        .padding(.top, 14)
                    reshootButton
                        .padding(.top, 14)
                    TitleEditField(
                        title: $title, candidates: recognition.candidates, isRecognizing: recognition.isRecognizing,
                        label: "題名",
                        note: "必須", focus: $titleFocused, idPrefix: "edit"
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    infoCard
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    Text("本の削除は、棚で長押し → 下スワイプ")
                        .font(BookshelfStyle.sans(11))
                        .foregroundStyle(BookshelfStyle.faint)
                        .padding(.top, 26)
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task(id: book.id) {
            // 撮り直しの画面から戻ったときにもう一度読まない（表紙をもう出している）
            guard cover == nil else { return }
            let original = await CoverImageCache.shared.original(for: book.id, in: store.images)
            // 読み込みの間に撮り直していたら、新しい表紙のほうを残す（N-071）
            guard newCover == nil else { return }
            cover = original
            recognition.start(store.images.loadOriginal(for: book.id))
        }
        .sheet(isPresented: $showsGenrePicker) {
            GenrePickerSheet(shelves: selectableShelves, selected: shelf?.persistentModelID) { picked in
                shelf = picked
                showsGenrePicker = false
            }
        }
        .sheet(isPresented: $showsDatePicker) {
            PurchaseDateSheet(date: $purchaseDate) { showsDatePicker = false }
        }
        .fullScreenCover(item: $reshoot) { model in
            CoverReshootView(
                model: model,
                onCaptured: { processed in
                    reshoot = nil
                    newCover = processed
                    cover = UIImage(data: processed.image)
                    recognition.start(processed.image)
                },
                onCancel: { reshoot = nil })
        }
        .alert(
            "うまくいきませんでした",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {
                if closesAfterError { onSaved(false) }
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: 上

    private var header: some View {
        ZStack {
            Text("本を編集")
                .font(BookshelfStyle.sans(16, .medium))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("キャンセル", action: onCancel)
                    .font(BookshelfStyle.sans(15))
                    .foregroundStyle(BookshelfStyle.ink)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("edit.cancel")
                Spacer()
                Button(action: save) {
                    Text("完了")
                        .font(BookshelfStyle.sans(15, .medium))
                        .foregroundStyle(canSave ? BookshelfStyle.ink : BookshelfStyle.faint)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!canSave)
                .accessibilityIdentifier("edit.done")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
        .padding(.top, 4)
    }

    private var coverView: some View {
        Group {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(BookshelfStyle.fill)
                    .aspectRatio(0.7, contentMode: .fit)
            }
        }
        .frame(maxWidth: 130, maxHeight: 156)
        .accessibilityElement()
        .accessibilityLabel(newCover == nil ? "表紙" : "撮り直した表紙")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("edit.cover")
    }

    /// 「表紙を撮り直す」（FILL の丸い地・高さ 30。Figma 49:23576）
    private var reshootButton: some View {
        Button(action: startReshoot) {
            HStack(spacing: 6) {
                Image(systemName: "camera")
                    .font(.system(size: 13, weight: .regular))
                Text("表紙を撮り直す")
                    .font(BookshelfStyle.sans(13, .medium))
                    .tracking(0.5)
            }
            .foregroundStyle(BookshelfStyle.ink)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(BookshelfStyle.fill))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit.reshoot")
    }

    // MARK: カード（ジャンル・所持状況・購入日）

    private var infoCard: some View {
        VStack(spacing: 0) {
            Button {
                showsGenrePicker = true
            } label: {
                HStack {
                    Text("ジャンル")
                        .font(BookshelfStyle.sans(14))
                        .foregroundStyle(BookshelfStyle.sub)
                    Spacer()
                    Text(shelfName)
                        .font(BookshelfStyle.serif(15))
                        .foregroundStyle(BookshelfStyle.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BookshelfStyle.faint)
                }
                .tracking(0.3)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ジャンル")
            .accessibilityValue(shelfName)
            .accessibilityIdentifier("edit.genre")
            separator
            HStack {
                Text("所持状況")
                    .font(BookshelfStyle.sans(14))
                    .tracking(0.3)
                    .foregroundStyle(BookshelfStyle.sub)
                Spacer()
                OwnershipSwitch(ownership: ownership) { setOwnership($0) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("edit.ownershipRow")
            separator
            dateRow
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(BookshelfStyle.fill))
    }

    /// 購入日の行。「買いたい」のときは入力できず、案内を出す（§10.3）
    private var dateRow: some View {
        HStack {
            Text("購入日")
                .font(BookshelfStyle.sans(14))
                .tracking(0.3)
                .foregroundStyle(ownership == .owned ? BookshelfStyle.sub : BookshelfStyle.faint)
            Spacer()
            if ownership == .owned {
                Button {
                    showsDatePicker = true
                } label: {
                    Text(BookDates.format(purchaseDate))
                        .font(BookshelfStyle.sans(15))
                        .foregroundStyle(BookshelfStyle.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.white))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("購入日")
                .accessibilityValue(BookDates.format(purchaseDate))
                .accessibilityIdentifier("edit.purchaseDate")
            } else {
                Text("購入済みにすると今日の日付が入ります")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(BookshelfStyle.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("購入日")
                    .accessibilityValue("購入済みにすると今日の日付が入ります")
                    .accessibilityIdentifier("edit.purchaseDateDisabled")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var separator: some View {
        Rectangle()
            .fill(BookshelfStyle.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private var shelfName: String { shelf?.name ?? "未分類" }

    private var selectableShelves: [Shelf] {
        do {
            return try store.shelves().filter { $0.kind != .wishlist }
        } catch {
            Self.logger.error("棚の一覧を読めない: \(error.localizedDescription, privacy: .public)")
            return shelf.map { [$0] } ?? []
        }
    }

    // MARK: 操作

    /// 所持状況の切り替え。「購入済み」にしたときは購入日を今日にする（§10.3）
    private func setOwnership(_ value: Ownership) {
        guard value != ownership else { return }
        ownership = value
        if value == .owned {
            purchaseDate = Calendar.current.startOfDay(for: .now)
        }
    }

    private func startReshoot() {
        titleFocused = false
        do {
            reshoot = CaptureViewModel(
                store: store, camera: environment.makeCamera(), destination: try shelf ?? store.unsortedShelf(),
                recent: environment.recent, screen: .camera, purpose: .reshoot)
        } catch {
            Self.logger.error("撮影を始められない: \(error.localizedDescription, privacy: .public)")
            errorMessage = "撮影を始められませんでした"
        }
    }

    private func save() {
        do {
            let edit = BookEdit(
                title: title, shelf: try shelf ?? store.unsortedShelf(), ownership: ownership,
                purchaseDate: ownership == .owned ? purchaseDate : nil)
            try store.updateBook(book, with: edit, newCover: newCover)
            if newCover != nil {
                CoverImageCache.shared.invalidate(book.id)
            }
            onSaved(newCover != nil)
        } catch LibraryError.coverNotReplaced {
            Self.logger.error("表紙を入れ替えられない")
            closesAfterError = true
            errorMessage = "表紙を入れ替えられませんでした。ほかの変更は保存しました"
        } catch {
            Self.logger.error("本を保存できない: \(error.localizedDescription, privacy: .public)")
            errorMessage = "保存できませんでした。もう一度お試しください"
        }
    }
}

// MARK: - 題名の入力欄（E-6・E-7・C-3 で共通）

/// 題名の入力欄と、文字認識（OCR）の題名候補（F2-1〜F2-3: 候補を採用・修正・破棄できる。手入力も可）。
/// 白い地・INK の線・角 12・高さ 50（Figma 49:23590）。候補はタップで欄に入り、そのあと修正できる
struct TitleEditField: View {
    @Binding var title: String
    let candidates: [String]
    let isRecognizing: Bool
    /// 左上の項目名（「題名」「題名（必須）」）
    let label: String
    /// 右上の補足（「必須」など）。nil なら候補の状態（読み取り中・候補なし）を出す
    let note: String?
    var focus: FocusState<Bool>.Binding
    /// アクセシビリティ ID の頭（edit・titleEditor）
    let idPrefix: String
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
    /// ユーザーが欄を触った・候補を選んだ
    var onEdited: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(BookshelfStyle.sans(13, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                Spacer()
                Text(note ?? recognitionNote)
                    .font(BookshelfStyle.sans(11))
                    .foregroundStyle(BookshelfStyle.faint)
                    .accessibilityIdentifier("\(idPrefix).titleNote")
            }
            TextField(
                "",
                text: Binding(
                    get: { title },
                    set: { newValue in
                        title = newValue
                        onEdited()
                    }),
                prompt: Text("題名を入力").foregroundStyle(BookshelfStyle.faint)
            )
            .font(BookshelfStyle.serif(18))
            .foregroundStyle(BookshelfStyle.ink)
            .tint(BookshelfStyle.ink)
            .focused(focus)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .stroke(BookshelfStyle.ink, lineWidth: 1.5)
            )
            .accessibilityLabel("題名")
            .accessibilityIdentifier("\(idPrefix).title")
            candidateChips
        }
    }

    private var recognitionNote: String {
        if isRecognizing { return "表紙から読み取り中…" }
        return candidates.isEmpty ? "文字認識の候補なし" : "文字認識の候補あり"
    }

    /// 文字認識の候補（題名らしい順に最大3つ）。タップで題名欄に入れる
    @ViewBuilder
    private var candidateChips: some View {
        if isRecognizing && note != nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("表紙から題名の候補を読み取り中…")
                    .font(BookshelfStyle.sans(11))
                    .foregroundStyle(BookshelfStyle.sub)
            }
            .accessibilityIdentifier("\(idPrefix).recognizing")
        } else if !candidates.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("候補")
                        .font(BookshelfStyle.sans(11))
                        .foregroundStyle(BookshelfStyle.sub)
                    ForEach(Array(candidates.prefix(3).enumerated()), id: \.offset) { index, candidate in
                        Button {
                            title = candidate
                            onEdited()
                        } label: {
                            Text(candidate)
                                .font(BookshelfStyle.serif(13))
                                .foregroundStyle(BookshelfStyle.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Capsule().fill(BookshelfStyle.fill))
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("候補 \(candidate)")
                        .accessibilityHint("題名に入れます")
                        .accessibilityIdentifier("\(idPrefix).candidate.\(index)")
                    }
                }
            }
        } else if note != nil {
            Text("文字認識の候補なし")
                .font(BookshelfStyle.sans(11))
                .foregroundStyle(BookshelfStyle.faint)
                .accessibilityIdentifier("\(idPrefix).noCandidates")
        }
    }
}

// MARK: - 所持状況の切り替え

/// 「購入済み｜買いたい」（白い地・角 18・内側 3 に 76×30 の2つ。選択中は INK の地・白文字。design-brief §3）
struct OwnershipSwitch: View {
    let ownership: Ownership
    let onSelect: (Ownership) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("購入済み", .owned, id: "edit.ownership.owned")
            segment("買いたい", .wanted, id: "edit.ownership.wanted")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
    }

    private func segment(_ label: String, _ value: Ownership, id: String) -> some View {
        let selected = ownership == value
        return Button {
            onSelect(value)
        } label: {
            Text(label)
                .font(BookshelfStyle.sans(13, selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.white : BookshelfStyle.sub)
                .frame(width: 76, height: 30)
                .background(Capsule().fill(selected ? BookshelfStyle.ink : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("所持状況 \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - ジャンルを選ぶ

/// 編集画面のジャンルの行から出す一覧（買いたい本の棚は選べない。D-2・G-3 と同じ行の形: 高さ 48・選択中は FILL・チェック）
struct GenrePickerSheet: View {
    let shelves: [Shelf]
    let selected: PersistentIdentifier?
    let onSelect: (Shelf) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("ジャンルを選ぶ")
                .font(BookshelfStyle.sans(16, .medium))
                .foregroundStyle(BookshelfStyle.ink)
                .padding(.top, 24)
                .padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shelves) { shelf in
                            row(shelf).id(shelf.persistentModelID)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    if let selected { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private func row(_ shelf: Shelf) -> some View {
        let isSelected = shelf.persistentModelID == selected
        return Button {
            onSelect(shelf)
        } label: {
            HStack {
                Text(shelf.name)
                    .font(BookshelfStyle.serif(16))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BookshelfStyle.ink)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? BookshelfStyle.fill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("edit.genre.row.\(shelf.name)")
    }
}

// MARK: - 購入日を選ぶ

/// 購入日（日付だけ）。今日より先の日付は選べない
struct PurchaseDateSheet: View {
    @Binding var date: Date
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("完了", action: onDone)
                    .font(BookshelfStyle.sans(15, .medium))
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityIdentifier("edit.dateDone")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            DatePicker(
                "購入日",
                selection: Binding(get: { date }, set: { date = Calendar.current.startOfDay(for: $0) }),
                in: ...Date.now, displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(BookshelfStyle.ink)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("edit.datePicker")
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
    }
}

// MARK: - 表紙の撮り直し

/// 表紙の撮り直し（F6-4）。T5 の撮影画面・四隅の検出と補正・手動調整（N 画面）をそのまま使い、1枚撮ったら戻る。
/// 撮った表紙はまだ保存しない（編集画面の「完了」で保存する。キャンセルなら古い表紙のまま）
struct CoverReshootView: View {
    @State private var model: CaptureViewModel
    let onCaptured: (ProcessedCover) -> Void
    let onCancel: () -> Void

    init(model: CaptureViewModel, onCaptured: @escaping (ProcessedCover) -> Void, onCancel: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onCaptured = onCaptured
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            CaptureView(model: model, onClose: onCancel)
            if let adjustment = model.adjustments.first {
                CornerAdjustView(model: model, adjustment: adjustment)
                    .id(adjustment.id)
                    .transition(.opacity)
            }
        }
        .onChange(of: model.items.first?.id) { _, id in
            guard id != nil, let item = model.items.first else { return }
            onCaptured(ProcessedCover(image: item.image, thumbnail: item.thumbnail, corners: nil))
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

/// 編集画面の題名の候補を表紙から読み取る（N-071）。
/// 読み取りは1つだけ持ち、新しい表紙で始めたら前の読み取りを取り消す。前の読み取りが後から終わっても結果は捨て、
/// 「読み取り中」は最新の読み取りが終わったときにだけ解除する
@MainActor
@Observable
final class TitleCandidateLoader {
    private(set) var candidates: [String] = []
    private(set) var isRecognizing = true
    @ObservationIgnored private let recognize: @Sendable (Data) async -> [String]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 始めた読み取りの通し番号（最新でない読み取りの結果を捨てるため）
    @ObservationIgnored private var generation = 0

    init(recognize: @escaping @Sendable (Data) async -> [String] = { await TitleRecognizer().candidates(in: $0) }) {
        self.recognize = recognize
    }

    /// 表紙 `data` から読み取りを始める（前の読み取りは取り消す）。data が無ければ候補なし
    @discardableResult
    func start(_ data: Data?) -> Task<Void, Never> {
        task?.cancel()
        generation += 1
        let current = generation
        candidates = []
        isRecognizing = true
        let recognize = self.recognize
        let task = Task { [weak self] in
            let result: [String]
            if let data {
                result = await recognize(data)
            } else {
                result = []
            }
            guard let self, !Task.isCancelled, current == self.generation else { return }
            self.candidates = result
            self.isRecognizing = false
        }
        self.task = task
        return task
    }
}
