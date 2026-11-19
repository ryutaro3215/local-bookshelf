import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
import Vision

@testable import Bookshelf

/// plan.md T11 の acceptance（ShareRendererTests ①〜⑤）と、冊数による見せ方の切り替え・ストーリーズの余白・題名の折り返し。
/// 題名はすべて架空（DebugSeed の語の組み合わせ）、表紙は合成画像。
/// ⑤の生成時間を正しく測るため直列に実行する（並行だと他のテストの描画・文字認識を MainActor で待つ時間が入る）
@MainActor
@Suite(.serialized)
struct ShareRendererTests {
    let store: LibraryStore
    let folder: URL
    let calendar = Calendar.current

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Shelf.self, configurations: config)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ShareRendererTests-\(UUID().uuidString)", isDirectory: true)
        store = LibraryStore(container: container, images: ImageStore(directory: folder))
        try store.seedIfNeeded()
    }

    // MARK: - 準備

    func genre(_ name: String) throws -> Shelf {
        try #require(try store.shelves().first(where: { $0.name == name }))
    }

    func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    /// 合成の表紙つきで本を足す。表紙のサムネイルには位置情報（GPS）を入れておく（④で消えることを確かめる）
    @discardableResult
    func add(
        _ count: Int, to name: String, ownership: Ownership = .owned, on day: Date? = nil, serial start: Int = 0
    ) throws -> [Book] {
        let shelf = try genre(name)
        var books: [Book] = []
        for offset in 0..<count {
            let serial = start + offset
            let title = DebugSeed.title(serial)
            let id = UUID()
            let cover = DebugSeed.cover(title: title, serial: serial)
            try store.images.save(original: cover.original, thumbnail: try withGPS(cover.thumbnail), for: id)
            books.append(
                try store.addBook(
                    title: title, shelf: shelf, ownership: ownership,
                    now: day ?? Date(timeIntervalSinceNow: Double(serial - 10_000)), id: id))
        }
        return books
    }

    /// JPEG に GPS の情報を足す
    func withGPS(_ data: Data) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 35.6812, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 139.7671, kCGImagePropertyGPSLongitudeRef: "E",
        ]
        CGImageDestinationAddImageFromSource(
            destination, source, 0, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func pixelSize(_ data: Data) throws -> CGSize {
        let values = try properties(data)
        let width = try #require(values[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(values[kCGImagePropertyPixelHeight] as? Int)
        return CGSize(width: width, height: height)
    }

    /// 生成と、かかった時間（表紙の読み込みを含む）
    func render(_ content: ShareContent, _ format: ShareFormat) async throws -> (ShareImage, Duration) {
        let clock = ContinuousClock()
        let start = clock.now
        let image = try await ShareRenderer.render(content, format: format, images: store.images)
        return (image, clock.now - start)
    }

    /// ジャンル30冊・日3冊・月9冊（acceptance ①⑤の3つの単位）
    func acceptanceContents() throws -> [(String, ShareContent)] {
        let genreBooks = try add(30, to: "哲学・思想")
        try add(3, to: "哲学・思想", ownership: .wanted, serial: 100)
        let day = try date(2026, 10, 20)
        try add(3, to: "小説", on: day, serial: 200)
        try add(4, to: "エッセイ", on: try date(2026, 10, 5), serial: 300)
        try add(2, to: "小説", on: try date(2026, 10, 28), serial: 400)
        try add(1, to: "小説", ownership: .wanted, on: day, serial: 500)
        let months = MonthGrouping.groups(of: try store.context.fetch(FetchDescriptor<Book>()), by: .month)
        let october = try #require(months.first { $0.year == 2026 && $0.month == 10 })
        let dayBooks = october.books.filter { $0.purchaseDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        let owned = store.books(in: try genre("哲学・思想"))
        #expect(owned.map(\.id) == genreBooks.map(\.id))
        return [
            ("ジャンル30冊", ShareContent.make(scope: .genre("哲学・思想"), books: try genre("哲学・思想").books)),
            ("日3冊", ShareContent.make(scope: .day(day), books: dayBooks)),
            ("月9冊", ShareContent.make(scope: .month(year: 2026, month: 10), books: october.books)),
        ]
    }

    // MARK: - ①⑤ 大きさと生成時間

    @Test("① ジャンル30冊・日3冊・月9冊で 1080×1350 と 1080×1920 の画像ができる ⑤ それぞれ3秒以内")
    func rendersBothSizesWithinThreeSeconds() async throws {
        for (name, content) in try acceptanceContents() {
            for format in ShareFormat.allCases {
                var (image, elapsed) = try await render(content, format)
                // ほかのスイートと並行に走ると MainActor の空き待ちが混ざるので、3秒を超えたら測り直して最短で判定する
                for _ in 0..<2 where elapsed >= .seconds(3) {
                    let again = try await render(content, format)
                    image = again.0
                    elapsed = min(elapsed, again.1)
                }
                let size = try pixelSize(image.data)
                #expect(size == format.size, "\(name) \(format): \(size)")
                #expect(image.image.size == format.size, "\(name) \(format)")
                #expect(elapsed < .seconds(3), "\(name) \(format): \(elapsed)")
            }
        }
    }

    @Test("① 冊数がそろっている（ジャンル30・日3・月9）")
    func countsMatchTheScope() throws {
        let counts = try acceptanceContents().map { $0.1.books.count }
        #expect(counts == [30, 3, 9])
    }

    // MARK: - ② 「買いたい」の本を含めない

    @Test("② 「買いたい」の本はジャンル・日・月のどれにも含まれない")
    func excludesWantedBooks() throws {
        let contents = try acceptanceContents()
        let wanted = Set(
            try store.context.fetch(FetchDescriptor<Book>()).filter { $0.ownership == .wanted }.map(\.id))
        #expect(wanted.count == 4)
        for (name, content) in contents {
            #expect(content.books.allSatisfy { !wanted.contains($0.id) }, "\(name)")
            #expect(content.total == content.books.count, "\(name)")
        }
        // 「買いたい」だけを渡しても、画像に載る本は0冊
        let onlyWanted = try store.context.fetch(FetchDescriptor<Book>()).filter { $0.ownership == .wanted }
        #expect(ShareContent.make(scope: .genre("x"), books: onlyWanted).books.isEmpty)
    }

    // MARK: - ③ アプリ名

    @Test("③ 右下にアプリ名が入る（配置と、画像の文字認識の両方で確かめる）")
    func includesAppName() async throws {
        for (name, content) in try acceptanceContents() {
            for format in ShareFormat.allCases {
                var aspects: [UUID: CGFloat] = [:]
                for book in content.books { aspects[book.id] = 0.7 }
                let layout = ShareLayoutEngine.layout(content, format: format, aspects: aspects)
                #expect(layout.appName == "local-bookshelf", "\(name) \(format)")
                let (image, _) = try await render(content, format)
                let text = try recognizedText(image.image, bottomFraction: format == .story ? 0.32 : 0.12)
                #expect(text.lowercased().contains("bookshelf"), "\(name) \(format): \(text)")
            }
        }
    }

    /// 画像の下の帯の文字を読む（Vision。端末の中で行う）
    func recognizedText(_ image: UIImage, bottomFraction: CGFloat) throws -> String {
        let cgImage = try #require(image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        // Vision の座標は左下が原点
        request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: bottomFraction)
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    // MARK: - ④ 位置情報が無い

    @Test("④ 表紙に位置情報があっても、共有画像に EXIF の位置情報（GPS）が無い")
    func hasNoLocationMetadata() async throws {
        let contents = try acceptanceContents()
        // 前提: 表紙のサムネイルには GPS が入っている
        let anyBook = try #require(contents.first?.1.books.first)
        let thumbnail = try #require(store.images.loadThumbnail(for: anyBook.id))
        #expect(try properties(thumbnail)[kCGImagePropertyGPSDictionary] != nil)
        for (name, content) in contents {
            for format in ShareFormat.allCases {
                let (image, _) = try await render(content, format)
                let values = try properties(image.data)
                #expect(values[kCGImagePropertyGPSDictionary] == nil, "\(name) \(format)")
                let exif = values[kCGImagePropertyExifDictionary] as? [CFString: Any]
                #expect(exif?[kCGImagePropertyExifUserComment] == nil, "\(name) \(format)")
            }
        }
    }

    // MARK: - 冊数による見せ方（design-brief §7）

    @Test("1〜12冊は表紙＋題名、13〜40冊は表紙だけ、41冊〜はモザイクと大きな数字")
    func switchesStyleByCount() throws {
        #expect(ShareStyleKind.forCount(1) == .coversWithTitles)
        #expect(ShareStyleKind.forCount(12) == .coversWithTitles)
        #expect(ShareStyleKind.forCount(13) == .coversOnly)
        #expect(ShareStyleKind.forCount(40) == .coversOnly)
        #expect(ShareStyleKind.forCount(41) == .mosaic)
        let books = try add(45, to: "哲学・思想")
        let aspects = Dictionary(uniqueKeysWithValues: books.map { ($0.id, CGFloat(0.7)) })
        let small = ShareLayoutEngine.layout(
            .make(scope: .genre("哲学・思想"), books: Array(books.prefix(9))), format: .portrait, aspects: aspects)
        #expect(small.style == .coversWithTitles)
        #expect(small.covers.allSatisfy { !$0.titleLines.isEmpty && $0.titleLines.count <= 2 })
        let middle = ShareLayoutEngine.layout(
            .make(scope: .genre("哲学・思想"), books: Array(books.prefix(24))), format: .portrait, aspects: aspects)
        #expect(middle.style == .coversOnly)
        #expect(middle.covers.allSatisfy { $0.titleLines.isEmpty })
        #expect(middle.labels.map(\.text) == ["哲学・思想"])
        let large = ShareLayoutEngine.layout(
            .make(scope: .genre("哲学・思想"), books: books), format: .portrait, aspects: aspects)
        #expect(large.style == .mosaic)
        #expect(large.bigNumber == "45")
        #expect(large.covers.count == 45)
    }

    @Test("表紙どうし・画像の外に、はみ出さない（4:5・9:16 と各見せ方）")
    func coversStayInsideAndDoNotOverlap() throws {
        let books = try add(60, to: "哲学・思想")
        let aspects = Dictionary(
            uniqueKeysWithValues: books.enumerated().map { ($1.id, CGFloat([0.62, 0.7, 0.75][$0 % 3])) })
        for count in [1, 3, 9, 12, 24, 40, 60] {
            for format in ShareFormat.allCases {
                let content = ShareContent.make(scope: .genre("哲学・思想"), books: Array(books.prefix(count)))
                let layout = ShareLayoutEngine.layout(content, format: format, aspects: aspects)
                #expect(layout.covers.count == count)
                let canvas = CGRect(origin: .zero, size: format.size)
                // ストーリーズは上 14%・下 20% に背景以外を置かない
                let safe = CGRect(
                    x: 0, y: format.safeTop, width: canvas.width,
                    height: canvas.height - format.safeTop - format.safeBottom)
                for (index, cover) in layout.covers.enumerated() {
                    #expect(safe.contains(cover.frame.insetBy(dx: 0.5, dy: 0.5)), "\(count)冊 \(format) #\(index)")
                    if !cover.titleLines.isEmpty {
                        #expect(safe.contains(cover.titleFrame.insetBy(dx: 0.5, dy: 0.5)), "\(count)冊 \(format) 題名")
                    }
                    for other in layout.covers[(index + 1)...] {
                        #expect(!cover.frame.insetBy(dx: 0.5, dy: 0.5).intersects(other.frame), "\(count)冊 \(format)")
                    }
                }
                #expect(layout.footerY + 30 <= canvas.height - format.safeBottom, "\(count)冊 \(format) 下の文字")
            }
        }
    }

    @Test("300冊を超えたら最新の300冊を載せ、「ほか○冊」と書く")
    func capsAtThreeHundred() throws {
        let books = try add(305, to: "哲学・思想")
        let content = ShareContent.make(scope: .genre("哲学・思想"), books: books)
        #expect(content.total == 305)
        #expect(content.books.count == 300)
        #expect(content.omitted == 5)
        // データ追加日の古い5冊（serial 0〜4）が外れる
        #expect(Set(content.books.map(\.id)) == Set(books.suffix(300).map(\.id)))
        #expect(content.fact.contains("5"))
    }

    @Test("月は区分（ジャンル）ごとに分け、2つ目の区分に帯を敷く。区分名は右端に縦書き")
    func monthIsSplitByGenre() throws {
        try add(5, to: "哲学・思想", on: try date(2026, 10, 3))
        try add(4, to: "歴史", on: try date(2026, 10, 9), serial: 50)
        let groups = MonthGrouping.groups(of: try store.context.fetch(FetchDescriptor<Book>()), by: .month)
        let october = try #require(groups.first)
        let content = ShareContent.make(scope: .month(year: 2026, month: 10), books: october.books)
        #expect(content.sections.map(\.name) == [try genre("哲学・思想").displayName, try genre("歴史").displayName])
        #expect(content.sections.map(\.books.count) == [5, 4])
        let layout = ShareLayoutEngine.layout(content, format: .story, aspects: [:])
        #expect(layout.bands.count == 1)
        #expect(layout.labels.count == 2)
    }

    @Test("ジャンルの多い月は区分に分けず1つの格子にまとめ、区分名を出さない。表紙は小さくなりすぎず、はみ出さない")
    func manyGenresAreMergedIntoOneGrid() throws {
        let shelves = try store.shelves().filter { $0.kind != .unsorted && $0.kind != .wishlist }
        let day = try date(2026, 10, 10)
        var serial = 0
        // (ジャンルの数, 1ジャンルあたりの冊数)
        for (genres, perGenre) in [(3, 1), (4, 1), (6, 1), (8, 1), (12, 1), (10, 2), (20, 2)] {
            try #require(shelves.count >= genres)
            var books: [Book] = []
            for shelf in shelves.prefix(genres) {
                books += try add(perGenre, to: shelf.name, on: day, serial: serial)
                serial += perGenre
            }
            let content = ShareContent.make(scope: .month(year: 2026, month: 10), books: books)
            #expect(content.sections.count == genres)
            let aspects = Dictionary(uniqueKeysWithValues: books.map { ($0.id, CGFloat(0.7)) })
            for format in ShareFormat.allCases {
                let name = "\(genres)ジャンル×\(perGenre)冊 \(format)"
                let layout = ShareLayoutEngine.layout(content, format: format, aspects: aspects)
                #expect(layout.covers.count == genres * perGenre, "\(name)")
                // CGRect.height は絶対値なので size で負でないことを見る
                let heights = layout.covers.map(\.frame.size.height)
                #expect(heights.allSatisfy { $0 >= ShareLayoutEngine.minimumSectionedCover }, "\(name): \(heights)")
                // 区分に分けるなら区分名は全部、まとめるなら区分名も帯も無い
                #expect(layout.labels.count == genres || (layout.labels.isEmpty && layout.bands.isEmpty), "\(name)")
                #expect(layout.labels.allSatisfy { $0.frame.size.height >= ShareLayoutEngine.minimumSectionedCover })
                let safe = CGRect(
                    x: 0, y: format.safeTop, width: format.size.width,
                    height: format.size.height - format.safeTop - format.safeBottom)
                for (index, cover) in layout.covers.enumerated() {
                    #expect(safe.contains(cover.frame.insetBy(dx: 0.5, dy: 0.5)), "\(name) #\(index)")
                    if !cover.titleLines.isEmpty {
                        #expect(safe.contains(cover.titleFrame.insetBy(dx: 0.5, dy: 0.5)), "\(name) 題名 #\(index)")
                    }
                    for other in layout.covers[(index + 1)...] {
                        #expect(!cover.frame.insetBy(dx: 0.5, dy: 0.5).intersects(other.frame), "\(name)")
                    }
                }
            }
            // 4ジャンル以上・1冊ずつはまとめる
            if genres >= 4 && perGenre == 1 {
                let layout = ShareLayoutEngine.layout(content, format: .portrait, aspects: aspects)
                #expect(layout.labels.isEmpty, "\(genres)ジャンル")
            }
        }
    }

    @Test("題名は「の」「・」の切れ目で2行に折り返し、入らなければ小さくして「…」")
    func breaksTitlesAtNaturalPoints() {
        // 1文字の幅 = 文字の大きさ（全角）とする
        let measure: ShareLayoutEngine.Measure = { text, size in CGFloat(text.count) * size }
        let fitted = ShareTitle.lines("トワイライトの灯台", size: 30, width: 240, measure: measure)
        #expect(fitted.lines == ["トワイライトの", "灯台"])
        let dot = ShareTitle.lines("イタリア・ルネサンスの世界", size: 30, width: 260, measure: measure)
        #expect(dot.lines.count == 2)
        #expect(dot.lines.joined() == "イタリア・ルネサンスの世界")
        let short = ShareTitle.lines("青い温室論", size: 30, width: 240, measure: measure)
        #expect(short.lines == ["青い温室論"])
        #expect(short.size == 30)
        let long = ShareTitle.lines(String(repeating: "長", count: 40), size: 30, width: 240, measure: measure)
        #expect(long.lines.count == 2)
        #expect(long.lines[1].hasSuffix("…"))
        #expect(long.size < 30)
    }

    @Test("日の区分名は日付（2026.10.20 の形）。英数字だけなので回して置く")
    func dayLabelIsDate() throws {
        let day = try date(2026, 10, 20)
        let books = try add(3, to: "小説", on: day)
        let content = ShareContent.make(scope: .day(day), books: books)
        #expect(content.sections.map(\.name) == [BookDates.format(day)])
        let layout = ShareLayoutEngine.layout(content, format: .portrait, aspects: [:])
        #expect(layout.labels.first?.rotated == true)
    }
}
