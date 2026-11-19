import SwiftData
import SwiftUI
import UIKit

/// 未分類の本をジャンルに分ける画面（F5-4。2026-11-20 オーナー指示）。
/// 未分類の本を1冊ずつ並べ、本ごとにジャンルを選んで、最後に「保存」でまとめて移す（1冊ずつ編集を開かなくてよい）
struct SortIntoGenresView: View {
    /// 未分類の棚に並んでいる本（並び順のまま）
    let books: [Book]
    /// 選べるジャンル（買いたい本・未分類を除く。棚の並び順）
    let genres: [Shelf]
    let images: ImageStore
    let onCancel: () -> Void
    /// 選んだ本とジャンル（選んだ本だけ。未分類の並び順）
    let onSave: ([(book: Book, shelf: Shelf)]) -> Void
    /// 本の ID ごとに選んだジャンル
    @State private var chosen: [UUID: Shelf] = [:]

    private var moves: [(book: Book, shelf: Shelf)] {
        books.compactMap { book in chosen[book.id].map { (book, $0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("ジャンルに分ける")
                    .font(BookshelfStyle.sans(16, .medium))
                    .tracking(0.5)
                    .foregroundStyle(BookshelfStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sort.title")
                HStack {
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(BookshelfStyle.sans(15))
                            .foregroundStyle(BookshelfStyle.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sort.cancel")
                    Spacer()
                    Button {
                        onSave(moves)
                    } label: {
                        Text("保存")
                            .font(BookshelfStyle.sans(15, .medium))
                            .foregroundStyle(moves.isEmpty ? BookshelfStyle.faint : BookshelfStyle.ink)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(moves.isEmpty)
                    .accessibilityIdentifier("sort.save")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            Text(summary)
                .font(BookshelfStyle.sans(12))
                .tracking(0.3)
                .foregroundStyle(BookshelfStyle.sub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .accessibilityIdentifier("sort.summary")
            Rectangle().fill(BookshelfStyle.panelLine).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        SortIntoGenresRow(
                            book: book, genres: genres, images: images,
                            chosen: Binding(
                                get: { chosen[book.id] },
                                set: { chosen[book.id] = $0 }),
                            showsSeparator: index < books.count - 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(BookshelfStyle.background)
    }

    /// 「12冊のうち 3冊 を選びました」など
    private var summary: String {
        moves.isEmpty
            ? String(appLocalized: "本ごとにジャンルを選んで、まとめて保存します")
            : String(appLocalized: "\(books.count)冊のうち\(moves.count)冊のジャンルを選びました")
    }
}

/// 1冊分の行（表紙・題名・右にジャンルを選ぶメニュー）
struct SortIntoGenresRow: View {
    let book: Book
    let genres: [Shelf]
    let images: ImageStore
    @Binding var chosen: Shelf?
    let showsSeparator: Bool
    @State private var cover: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            coverView
                .frame(width: 40, height: 56)
                .accessibilityHidden(true)
            Text(book.title)
                .font(BookshelfStyle.serif(16, relativeTo: .body))
                .tracking(0.5)
                .foregroundStyle(BookshelfStyle.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Menu {
                Button {
                    chosen = nil
                } label: {
                    if chosen == nil {
                        Label(InitialGenres.unsortedDisplayName, systemImage: "checkmark")
                    } else {
                        Text(InitialGenres.unsortedDisplayName)
                    }
                }
                ForEach(groups, id: \.category.id) { group in
                    Section(group.category.displayName) {
                        ForEach(group.shelves, id: \.persistentModelID) { shelf in
                            Button {
                                chosen = shelf
                            } label: {
                                if shelf.persistentModelID == chosen?.persistentModelID {
                                    Label(shelf.displayName, systemImage: "checkmark")
                                } else {
                                    Text(shelf.displayName)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(chosen?.displayName ?? String(appLocalized: "ジャンルを選ぶ"))
                        .font(BookshelfStyle.sans(13, chosen == nil ? .regular : .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(chosen == nil ? BookshelfStyle.sub : BookshelfStyle.onInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(Capsule().fill(chosen == nil ? BookshelfStyle.fill : BookshelfStyle.ink))
                .frame(maxWidth: 160, alignment: .trailing)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(book.title)
            .accessibilityValue(chosen?.displayName ?? String(appLocalized: "ジャンルを選ぶ"))
            .accessibilityHint("ジャンルを選びます")
            .accessibilityIdentifier("sort.row.\(book.title)")
        }
        .frame(minHeight: 76)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(BookshelfStyle.panelLine)
                    .frame(height: 1)
                    .padding(.leading, 54)
            }
        }
        .task(id: book.id) {
            cover = CoverImageCache.shared.cachedThumbnail(for: book.id)
            if cover == nil {
                cover = await CoverImageCache.shared.thumbnail(for: book.id, in: images)
            }
        }
    }

    @ViewBuilder private var coverView: some View {
        if let cover {
            Image(uiImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(maxWidth: 40, maxHeight: 56)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(BookshelfStyle.fill)
                .frame(width: 38, height: 56)
        }
    }

    /// 区分ごとにまとめる（並びは棚の並び順のまま。移動先のシート D-2 と同じ）
    private var groups: [(category: GenreCategory, shelves: [Shelf])] {
        var result: [(category: GenreCategory, shelves: [Shelf])] = []
        for shelf in genres {
            let category = InitialGenres.categories.first { $0.id == shelf.categoryID } ?? InitialGenres.myGenres
            if let index = result.firstIndex(where: { $0.category.id == category.id }) {
                result[index].shelves.append(shelf)
            } else {
                result.append((category, [shelf]))
            }
        }
        return result
    }
}
