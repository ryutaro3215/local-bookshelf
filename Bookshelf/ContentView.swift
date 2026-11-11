import SwiftData
import SwiftUI

/// 仮の画面（T5）。撮影登録フローを動かして確かめるための最小限の入口。
/// T6 の閲覧画面（下部バーの＋・棚の末尾の空き枠）に置き換える
struct ContentView: View {
    let environment: AppEnvironment
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]
    @Query(sort: \Book.addedAt) private var books: [Book]
    @State private var methodRequest: MethodRequest?
    @State private var chosen: (start: RegistrationStart, destination: Shelf)?
    @State private var flow: CaptureViewModel?

    var body: some View {
        NavigationStack {
            List {
                Section("登録した本") {
                    ForEach(books) { book in
                        Text(describe(book))
                            .font(.caption)
                            .accessibilityIdentifier("host.book")
                    }
                }
                Section("棚（見る＝直前に使った棚として記録 / 空き枠＝その棚から登録）") {
                    ForEach(shelves) { shelf in
                        row(shelf)
                    }
                }
            }
            .navigationTitle("仮の入口（T6 で置き換え）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        // 入口 A: 下部バーの＋（F1-6 A。初期の棚は F1-5）
                        open(from: initialShelf())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("host.add")
                }
            }
        }
        .sheet(item: $methodRequest, onDismiss: beginChosenFlow) { request in
            MethodSheetHost(
                shelves: shelves.filter { $0.kind != .wishlist }, initial: request.destination,
                onSelect: { start, destination in
                    chosen = (start, destination)
                    methodRequest = nil
                },
                onCancel: { methodRequest = nil })
        }
        .fullScreenCover(item: $flow) { model in
            RegistrationFlowView(model: model) { _ in flow = nil }
        }
    }

    private func row(_ shelf: Shelf) -> some View {
        HStack {
            Text(shelf.name)
            Text("\(count(shelf))冊")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("host.count.\(shelf.name)")
            Spacer()
            Button("見る") { environment.recent.record(shelf) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("host.visit.\(shelf.name)")
            if shelf.kind != .wishlist {
                // 入口 B: 棚の末尾の空き枠（F1-6 B。買いたい本には出さない）
                Button("空き枠") { open(from: shelf) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("host.slot.\(shelf.name)")
            }
        }
        .font(.subheadline)
    }

    private func count(_ shelf: Shelf) -> Int {
        if shelf.kind == .wishlist {
            return books.filter { $0.ownership == .wanted }.count
        }
        return environment.store.books(in: shelf).count
    }

    private func describe(_ book: Book) -> String {
        let ownership = book.ownership == .owned ? "購入済み" : "買いたい"
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let date = book.purchaseDate.map { formatter.string(from: $0) } ?? "購入日なし"
        return "\(book.title)｜\(book.shelf?.name ?? "-")｜\(ownership)｜\(date)"
    }

    private func initialShelf() -> Shelf? {
        do {
            return try environment.recent.initialShelf(in: environment.store)
        } catch {
            return shelves.first { $0.kind == .unsorted }
        }
    }

    private func open(from shelf: Shelf?) {
        guard let shelf else { return }
        chosen = nil
        methodRequest = MethodRequest(destination: shelf)
    }

    /// シートが閉じきってから撮影登録フローを出す
    private func beginChosenFlow() {
        guard let (start, destination) = chosen else { return }
        chosen = nil
        let model = CaptureViewModel(
            store: environment.store, camera: environment.makeCamera(), destination: destination,
            recent: environment.recent, screen: start == .camera ? .camera : .pending)
        model.opensLibraryOnAppear = start == .library
        flow = model
    }
}

extension CaptureViewModel: Identifiable {}

/// 登録方法のシートを開く依頼（どの棚から始めたか）
struct MethodRequest: Identifiable {
    let id = UUID()
    let destination: Shelf
}

/// 登録方法のシート（A-2）の入れ物。シートの中で登録先を変えられるよう、状態をここで持つ
struct MethodSheetHost: View {
    let shelves: [Shelf]
    @State private var destination: Shelf
    let onSelect: (RegistrationStart, Shelf) -> Void
    let onCancel: () -> Void

    init(
        shelves: [Shelf], initial: Shelf, onSelect: @escaping (RegistrationStart, Shelf) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.shelves = shelves
        _destination = State(initialValue: initial)
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        RegistrationMethodSheet(
            shelves: shelves, destination: $destination, onSelect: { onSelect($0, destination) }, onCancel: onCancel)
    }
}
