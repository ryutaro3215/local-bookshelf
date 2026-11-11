import SwiftData
import SwiftUI

/// 棚を選ぶリストの1行分（棚・冊数）
struct ShelfPickerEntry: Identifiable {
    let shelf: Shelf
    let count: Int
    var id: PersistentIdentifier { shelf.persistentModelID }
}

/// 「棚を選ぶ」シート（G-3。F6-8）。棚の名前をタップすると開く。区分の見出し・冊数つきで、
/// 閲覧画面に出ている棚（本が入っている棚と買いたい本）だけを並べる。選んだ棚に移る
struct ShelfPickerSheet: View {
    let entries: [ShelfPickerEntry]
    let currentID: PersistentIdentifier?
    let onSelect: (Shelf) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("棚を選ぶ")
                    .font(BookshelfStyle.sans(17, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("本が入っている棚だけ")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(BookshelfStyle.sub)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.category.id) { group in
                            Text(group.category.name)
                                .font(BookshelfStyle.sans(11, .medium))
                                .tracking(1)
                                .foregroundStyle(BookshelfStyle.faint)
                                .padding(.horizontal, 26)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("picker.category.\(group.category.name)")
                            ForEach(group.entries) { entry in
                                row(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .onAppear {
                    if let currentID {
                        proxy.scrollTo(currentID, anchor: .center)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private func row(_ entry: ShelfPickerEntry) -> some View {
        let selected = entry.id == currentID
        return Button {
            onSelect(entry.shelf)
        } label: {
            HStack(spacing: 12) {
                Text(entry.shelf.name)
                    .font(BookshelfStyle.serif(16))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(entry.count)冊")
                    .font(BookshelfStyle.sans(12))
                    .foregroundStyle(BookshelfStyle.sub)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BookshelfStyle.ink)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? BookshelfStyle.fill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel(entry.shelf.name)
        .accessibilityValue("\(entry.count)冊")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("picker.row.\(entry.shelf.name)")
    }

    /// 区分ごとにまとめる（並びは棚の並び順のまま。区分が飛び飛びになっても見出しは1つ）
    private var groups: [(category: GenreCategory, entries: [ShelfPickerEntry])] {
        var result: [(category: GenreCategory, entries: [ShelfPickerEntry])] = []
        for entry in entries {
            let category =
                InitialGenres.categories.first { $0.id == entry.shelf.categoryID } ?? InitialGenres.myGenres
            if let index = result.firstIndex(where: { $0.category.id == category.id }) {
                result[index].entries.append(entry)
            } else {
                result.append((category, [entry]))
            }
        }
        return result
    }
}
