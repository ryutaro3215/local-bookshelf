import ImageIO
import SwiftData
import SwiftUI
import UIKit
import os

// MARK: - 共有の単位と中身（F8-6）

/// 共有の単位（F8-6）。ジャンル別はその棚、購入月別は「この日／この月／この年」
enum ShareScope: Hashable, Sendable {
    /// ジャンル（画面に出す棚の名前）
    case genre(String)
    /// その日に買った本
    case day(Date)
    /// その月に買った本
    case month(year: Int, month: Int)
    /// その年に買った本
    case year(Int)
}

/// 共有画像に載せる本1冊（画像の生成では @Model を持たず、値だけを使う）
struct ShareBook: Hashable, Sendable {
    let id: UUID
    let title: String
}

/// 共有画像の区分（右端に縦書きで名前を出す。2つ目以降は帯の色を変える。design-brief §7）
struct ShareSection: Hashable, Sendable {
    let name: String
    let books: [ShareBook]
}

/// 共有画像の中身（どの本を、どの区分で、どんな説明で載せるか）
struct ShareContent: Hashable, Sendable {
    /// 1枚に載せる上限（これを超えたら最新の300冊＋「ほか○冊」。design-brief §7）
    static let limit = 300

    let scope: ShareScope
    let sections: [ShareSection]
    /// 購入済みの本の冊数（上限で載せなかった本も含む）
    let total: Int
    /// 左下の事実（「2026年10月に買った本・12冊」など）
    let fact: String
    /// モザイク（41冊〜）の大きな数字の横の見出し（「2026年に買った本」・棚の名前）
    let heading: String
    /// モザイクの左下（期間「2026.01.01 – 2026.12.31」。ジャンルは冊数）
    let mosaicFooter: String

    var books: [ShareBook] { sections.flatMap(\.books) }

    /// 区分を1つにまとめた中身（区分名は空。区分の多い月・年を1つの格子に並べるとき）
    func mergingSections() -> ShareContent {
        ShareContent(
            scope: scope, sections: [ShareSection(name: "", books: books)], total: total, fact: fact,
            heading: heading, mosaicFooter: mosaicFooter)
    }
    /// 上限で載せなかった冊数
    var omitted: Int { total - books.count }

    /// 本から共有画像の中身を作る。「買いたい」の本は含めない（F8-6）。
    /// 並びは渡された順（ジャンル別は棚の並び順、購入月別は購入日の古い順）。月・年はジャンルごとの区分に分ける
    @MainActor
    static func make(scope: ShareScope, books: [Book], calendar: Calendar = .current) -> ShareContent {
        let owned = books.filter { $0.ownership == .owned }
        var shown = owned
        if owned.count > limit {
            // 購入日の新しい300冊を、元の並びのまま残す（同じ日はデータ追加日の新しいほう）
            let newest = Set(
                owned.sorted { lhs, rhs in
                    let left = lhs.purchaseDate ?? lhs.addedAt
                    let right = rhs.purchaseDate ?? rhs.addedAt
                    return left != right ? left > right : lhs.addedAt > rhs.addedAt
                }
                .prefix(limit).map(\.id))
            shown = owned.filter { newest.contains($0.id) }
        }
        let sections: [ShareSection]
        switch scope {
        case .genre(let name):
            sections = [ShareSection(name: name, books: shown.map(Self.value))]
        case .day(let date):
            sections = [ShareSection(name: BookDates.format(date), books: shown.map(Self.value))]
        case .month, .year:
            sections = Self.sectionsByGenre(shown)
        }
        let count = owned.count
        let period = ShareText.period(of: scope, calendar: calendar)
        var fact: String
        let heading: String
        let mosaicFooter: String
        switch scope {
        case .genre(let name):
            fact = String(localized: "\(count)冊")
            heading = name
            mosaicFooter = fact
        case .day, .month, .year:
            fact = String(localized: "\(period)に買った本・\(count)冊")
            heading = String(localized: "\(period)に買った本")
            mosaicFooter = ShareText.range(of: scope, calendar: calendar)
        }
        let omitted = count - shown.count
        if omitted > 0 {
            fact += String(localized: "（ほか\(omitted)冊）")
        }
        return ShareContent(
            scope: scope, sections: sections, total: count, fact: fact, heading: heading,
            mosaicFooter: omitted > 0 ? mosaicFooter + String(localized: "（ほか\(omitted)冊）") : mosaicFooter)
    }

    @MainActor
    private static func value(_ book: Book) -> ShareBook {
        ShareBook(id: book.id, title: book.title)
    }

    /// ジャンルの並び順で区分に分ける（未分類・棚の無い本は最後）。区分の中は渡された順
    @MainActor
    private static func sectionsByGenre(_ books: [Book]) -> [ShareSection] {
        var order: [String] = []
        var names: [String: String] = [:]
        var ranks: [String: Int] = [:]
        var buckets: [String: [ShareBook]] = [:]
        for book in books {
            let key = book.shelf.map { String(describing: $0.persistentModelID) } ?? "-"
            if buckets[key] == nil {
                order.append(key)
                names[key] = book.shelf?.displayName ?? InitialGenres.unsortedDisplayName
                ranks[key] = book.shelf.map { $0.kind == .unsorted ? Int.max - 1 : $0.sortOrder } ?? Int.max
            }
            buckets[key, default: []].append(value(book))
        }
        return
            order
            .enumerated()
            .sorted { lhs, rhs in
                let left = ranks[lhs.element] ?? Int.max
                let right = ranks[rhs.element] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { ShareSection(name: names[$0.element] ?? "", books: buckets[$0.element] ?? []) }
    }
}

// MARK: - 共有画像の文言（日付）

/// 共有画像・共有の画面に出す日付の文言。日本語表示は「2026年10月20日」、英語表示は端末のロケールの書式
enum ShareText {
    /// 「2026年10月20日」「2026年10月」「2026年」（事実・見出しの期間）
    static func period(of scope: ShareScope, calendar: Calendar = .current) -> String {
        switch scope {
        case .genre(let name):
            return name
        case .day(let date):
            return day(date)
        case .month(let year, let month):
            return PurchaseGroup(period: .month, year: year, month: month, books: []).displayTitle
        case .year(let year):
            return PurchaseGroup(period: .year, year: year, month: nil, books: []).displayTitle
        }
    }

    /// 「2026年10月20日」（英語表示は「October 20, 2026」）
    static func day(_ date: Date) -> String {
        guard !InitialGenres.displaysInEnglish else { return date.formatted(date: .long, time: .omitted) }
        return japanese("y年M月d日", date)
    }

    /// 「10月20日」（範囲の選択の補足。英語表示は「Oct 20」）
    static func shortDay(_ date: Date) -> String {
        guard !InitialGenres.displaysInEnglish else { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return japanese("M月d日", date)
    }

    /// モザイクの左下の期間「2026.01.01 – 2026.12.31」
    static func range(of scope: ShareScope, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let start: Date?
        let end: Date?
        switch scope {
        case .genre:
            return ""
        case .day(let date):
            return BookDates.format(date)
        case .month(let year, let month):
            start = gregorian.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
            end = start.flatMap { gregorian.date(byAdding: DateComponents(month: 1, day: -1), to: $0) }
        case .year(let year):
            start = gregorian.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))
            end = gregorian.date(from: DateComponents(year: year, month: 12, day: 31, hour: 12))
        }
        guard let start, let end else { return "" }
        return "\(BookDates.format(start)) – \(BookDates.format(end))"
    }

    private static func japanese(_ format: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// MARK: - 画像の大きさ（F8-3）

/// 共有画像の縦横比。フィード・X・写真に保存は 4:5、ストーリーズは 9:16（design-brief §7）
enum ShareFormat: Hashable, Sendable, CaseIterable {
    /// 4:5（1080×1350）
    case portrait
    /// 9:16（1080×1920）
    case story

    var size: CGSize {
        switch self {
        case .portrait: CGSize(width: 1080, height: 1350)
        case .story: CGSize(width: 1080, height: 1920)
        }
    }

    /// ストーリーズの表示と重なる上の帯（上 14% には背景以外を置かない）
    var safeTop: CGFloat { self == .story ? (size.height * 0.14).rounded() : 0 }
    /// 返信欄と重なる下の帯（下 20% には背景以外を置かない）
    var safeBottom: CGFloat { self == .story ? (size.height * 0.20).rounded() : 0 }
}

// MARK: - 配置（design-brief §7）

/// 冊数による見せ方（上限なし。design-brief §7）
enum ShareStyleKind: Equatable, Sendable {
    /// 1〜12冊: 表紙＋題名
    case coversWithTitles
    /// 13〜40冊: 表紙だけ（帯と区分名は残す）
    case coversOnly
    /// 41冊〜: モザイク（高さをそろえて行ごとに隙間なく詰める）＋大きな数字
    case mosaic

    static func forCount(_ count: Int) -> ShareStyleKind {
        switch count {
        case ...12: .coversWithTitles
        case ...40: .coversOnly
        default: .mosaic
        }
    }
}

/// 置き場所の決まった表紙1冊
struct PlacedCover: Hashable, Sendable {
    let id: UUID
    let frame: CGRect
    /// 題名（表紙＋題名のときだけ。1〜2行）
    let titleLines: [String]
    let titleFrame: CGRect
    let titleSize: CGFloat
}

/// 右端の縦書きの区分名
struct PlacedLabel: Hashable, Sendable {
    let text: String
    /// 縦の帯（中心と長さ）
    let frame: CGRect
    let size: CGFloat
    /// 英数字だけの名前（日付・英語名）は90度回して置く。それ以外は1文字ずつ縦に積む
    let rotated: Bool
}

/// 共有画像1枚の配置（ShareTemplateView がこのとおりに描く）
struct ShareLayout: Sendable {
    let size: CGSize
    let style: ShareStyleKind
    let covers: [PlacedCover]
    /// 2つ目・4つ目…の区分の帯
    let bands: [CGRect]
    let labels: [PlacedLabel]
    /// 左下の事実と右下のアプリ名の、縦の中心
    let footerY: CGFloat
    let fact: String
    let appName: String
    /// モザイクの大きな数字と見出し（それ以外は nil）
    let bigNumber: String?
    let heading: String?
    let headerTop: CGFloat
}

/// 共有画像の配置を決める（数値は Figma の共有画像の行・1080 幅の画素）
enum ShareLayoutEngine {
    static let marginX: CGFloat = 56
    /// 右端の縦書きの区分名の列の幅
    static let labelColumn: CGFloat = 120
    static let sectionGap: CGFloat = 44

    /// 題名の長さを測る（既定は Noto Serif JP 700）
    typealias Measure = @MainActor (String, CGFloat) -> CGFloat

    @MainActor
    static func layout(
        _ content: ShareContent, format: ShareFormat, aspects: [UUID: CGFloat],
        measure: Measure = ShareFonts.titleWidth
    ) -> ShareLayout {
        let style = ShareStyleKind.forCount(content.books.count)
        let size = format.size
        let footerY = format == .story ? size.height - format.safeBottom - 40 : size.height - 90
        if style == .mosaic {
            return mosaic(content, format: format, aspects: aspects, footerY: footerY)
        }
        let sectioned = grid(
            content, format: format, style: style, aspects: aspects, footerY: footerY, measure: measure)
        guard content.sections.filter({ !$0.books.isEmpty }).count > 1 else { return sectioned.layout }
        // 区分（ジャンル）が多いと区分ごとに行と余白を取るので表紙が小さくなる。そのときは区分に分けず
        // 1つの格子にまとめ、区分名は出さない（2026-11-18 オーナー判断。T11 レビュー must）
        let merged = grid(
            content.mergingSections(), format: format, style: style, aspects: aspects, footerY: footerY,
            measure: measure)
        let keepsSections = sectioned.cover >= max(minimumSectionedCover, merged.cover * 0.6)
        return keepsSections ? sectioned.layout : merged.layout
    }

    /// 区分に分けたままにする表紙の高さの下限（これより小さければ1つの格子にまとめる。区分名の帯の高さも兼ねる）
    static let minimumSectionedCover: CGFloat = 120

    // MARK: 表紙を格子に並べる（1〜40冊）

    /// 格子の配置と、そのときの表紙の高さ（区分に分けるかどうかの比較に使う）
    @MainActor
    private static func grid(
        _ content: ShareContent, format: ShareFormat, style: ShareStyleKind, aspects: [UUID: CGFloat],
        footerY: CGFloat, measure: Measure
    ) -> (layout: ShareLayout, cover: CGFloat) {
        let size = format.size
        let titled = style == .coversWithTitles
        let left = marginX
        let width = size.width - labelColumn - left
        let top = format.safeTop + (format == .story ? 40 : 50)
        let bottom = footerY - 60
        let areaHeight = bottom - top
        let gapX: CGFloat = titled ? 40 : 24
        let gapY: CGFloat = titled ? 36 : 28
        let sections = content.sections.filter { !$0.books.isEmpty }
        let largest = sections.map(\.books.count).max() ?? 1
        // 表紙の縦横比の中央値（列の幅から表紙の高さの上限を決める）
        let ratios = content.books.compactMap { aspects[$0.id] }.sorted()
        let typical = min(max(ratios.isEmpty ? 0.68 : ratios[ratios.count / 2], 0.55), 0.85)
        let cap: CGFloat = content.books.count == 1 ? 560 : 420

        // 列の数を変えてみて、表紙がいちばん大きくなるものを選ぶ。最後の行の空きが多い並び（9冊を4列で4・4・1）は
        // 空きの割合で減点し、そろった格子（3×3）を選びやすくする。同じなら列の少ないほう
        var best: (columns: Int, cover: CGFloat, cell: CGFloat, title: CGFloat, score: CGFloat)?
        for columns in 1...min(max(largest, 1), 8) {
            let cell = (width - CGFloat(columns - 1) * gapX) / CGFloat(columns)
            let rows = sections.reduce(0) { $0 + Int(ceil(Double($1.books.count) / Double(columns))) }
            let titleSize = titled ? min(max(cell * 0.11, 20), 34) : 0
            let titleBlock = titled ? 20 + titleSize * 1.32 * 2 : 0
            let free =
                areaHeight - CGFloat(max(rows - 1, 0)) * gapY - CGFloat(max(sections.count - 1, 0)) * sectionGap
            let byHeight = free / CGFloat(max(rows, 1)) - titleBlock
            let cover = min(byHeight, cell / typical, cap)
            let filled = CGFloat(content.books.count) / CGFloat(max(rows * columns, 1))
            let score = cover * filled.squareRoot()
            if best == nil || score > (best?.score ?? 0) + 0.5 {
                best = (columns, cover, cell, titleSize, score)
            }
        }
        guard let best else {
            let empty = ShareLayout(
                size: size, style: style, covers: [], bands: [], labels: [], footerY: footerY, fact: content.fact,
                appName: ShareFonts.appName, bigNumber: nil, heading: nil, headerTop: 0)
            return (empty, 0)
        }
        let titleBlock = titled ? 20 + best.title * 1.32 * 2 : 0
        let rowHeight = best.cover + titleBlock
        let rowsPerSection = sections.map { Int(ceil(Double($0.books.count) / Double(best.columns))) }
        let blockHeight =
            rowsPerSection.reduce(0) { $0 + CGFloat($1) * rowHeight + CGFloat(max($1 - 1, 0)) * gapY }
            + CGFloat(max(sections.count - 1, 0)) * (gapY + sectionGap)
        // 格子のまとまりを、使える高さの中で上下中央に置く
        var y = top + max((areaHeight - blockHeight) / 2, 0)
        var covers: [PlacedCover] = []
        var bands: [CGRect] = []
        var labels: [PlacedLabel] = []
        for (sectionIndex, section) in sections.enumerated() {
            let sectionTop = y
            for (offset, book) in section.books.enumerated() {
                let row = offset / best.columns
                let column = offset % best.columns
                let cellX = left + CGFloat(column) * (best.cell + gapX)
                let cellY = sectionTop + CGFloat(row) * (rowHeight + gapY)
                let aspect = aspects[book.id] ?? typical
                // 縦横比のまま、セルの幅と表紙の高さに収める（各段は上端そろえ）
                var coverSize = CGSize(width: aspect * best.cover, height: best.cover)
                if coverSize.width > best.cell {
                    coverSize = CGSize(width: best.cell, height: best.cell / aspect)
                }
                let frame = CGRect(
                    x: cellX + (best.cell - coverSize.width) / 2, y: cellY, width: coverSize.width,
                    height: coverSize.height)
                var lines: [String] = []
                var titleSize: CGFloat = 0
                var titleFrame = CGRect.zero
                if titled {
                    let fitted = ShareTitle.lines(
                        book.title, size: best.title, width: best.cell + gapX * 0.6, measure: measure)
                    lines = fitted.lines
                    titleSize = fitted.size
                    titleFrame = CGRect(
                        x: cellX - gapX * 0.3, y: frame.maxY + 20, width: best.cell + gapX * 0.6,
                        height: fitted.size * 1.32 * CGFloat(lines.count))
                }
                covers.append(
                    PlacedCover(
                        id: book.id, frame: frame, titleLines: lines, titleFrame: titleFrame, titleSize: titleSize))
            }
            let rows = rowsPerSection[sectionIndex]
            let sectionHeight = CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * gapY
            let isLast = sectionIndex == sections.count - 1
            if sectionIndex % 2 == 1 {
                // 2つ目・4つ目…の区分は帯の色を変える。最後の区分の帯は画像の下端まで伸ばす（Figma の 9:16 月別）
                let bandTop = sectionTop - (gapY + sectionGap) / 2
                let bandBottom = isLast ? size.height : sectionTop + sectionHeight + (gapY + sectionGap) / 2
                bands.append(CGRect(x: 0, y: bandTop, width: size.width, height: bandBottom - bandTop))
            }
            // 名前の無い区分（区分をまとめた格子）には区分名を出さない
            if !section.name.isEmpty {
                labels.append(
                    label(
                        section.name,
                        in: CGRect(
                            x: size.width - labelColumn, y: sectionTop, width: labelColumn - 8,
                            height: sectionHeight)))
            }
            y = sectionTop + sectionHeight + gapY + sectionGap
        }
        let layout = ShareLayout(
            size: size, style: style, covers: covers, bands: bands, labels: labels, footerY: footerY,
            fact: content.fact, appName: ShareFonts.appName, bigNumber: nil, heading: nil, headerTop: 0)
        return (layout, best.cover)
    }

    /// 右端の縦書きの区分名。長さが帯に収まらなければ小さくする
    private static func label(_ text: String, in frame: CGRect) -> PlacedLabel {
        let rotated = text.unicodeScalars.allSatisfy { $0.isASCII }
        let count = CGFloat(max(text.count, 1))
        let available = max(frame.height - 20, 60)
        // 縦に積むと1文字あたり約 1.08 字分、回すと英数字は約 0.62 字分の長さになる
        let perChar: CGFloat = rotated ? 0.62 : 1.08
        let size = min(46, max(available / (count * perChar), 22))
        return PlacedLabel(text: text, frame: frame, size: size, rotated: rotated)
    }

    // MARK: モザイク（41冊〜）

    @MainActor
    private static func mosaic(
        _ content: ShareContent, format: ShareFormat, aspects: [UUID: CGFloat], footerY: CGFloat
    ) -> ShareLayout {
        let size = format.size
        let headerTop = format.safeTop + (format == .story ? 30 : 60)
        let left: CGFloat = 40
        let width = size.width - left * 2
        let top = headerTop + 255
        let bottom = footerY - 55
        let gap: CGFloat = 4
        let books = content.books
        let ratios = books.map { min(max(aspects[$0.id] ?? 0.68, 0.4), 1.5) }

        /// 行の高さ base で詰めたときの行（本の番号の範囲と、幅いっぱいにそろえた行の高さ）
        func rows(_ base: CGFloat) -> [(range: Range<Int>, height: CGFloat)] {
            var result: [(Range<Int>, CGFloat)] = []
            var start = 0
            var sum: CGFloat = 0
            for index in books.indices {
                let next = sum + ratios[index] * base
                let gaps = CGFloat(index - start) * gap
                if index > start, next + gaps > width {
                    let rowGaps = CGFloat(index - start - 1) * gap
                    result.append((start..<index, base * (width - rowGaps) / sum))
                    start = index
                    sum = ratios[index] * base
                } else {
                    sum = next
                }
            }
            if start < books.count {
                // 最後の行は縮めない（左寄せ）。幅を超えるときだけ幅に合わせる
                let rowGaps = CGFloat(books.count - start - 1) * gap
                result.append((start..<books.count, min(base, base * (width - rowGaps) / max(sum, 1))))
            }
            return result
        }
        func height(_ list: [(range: Range<Int>, height: CGFloat)]) -> CGFloat {
            list.reduce(0) { $0 + $1.height } + CGFloat(max(list.count - 1, 0)) * gap
        }
        // 収まるいちばん高い行の高さを二分探索で探す
        var low: CGFloat = 4
        var high: CGFloat = 400
        for _ in 0..<28 {
            let middle = (low + high) / 2
            if height(rows(middle)) <= bottom - top {
                low = middle
            } else {
                high = middle
            }
        }
        var covers: [PlacedCover] = []
        var y = top
        for row in rows(low) {
            var x = left
            for index in row.range {
                let frame = CGRect(x: x, y: y, width: ratios[index] * row.height, height: row.height)
                covers.append(
                    PlacedCover(id: books[index].id, frame: frame, titleLines: [], titleFrame: .zero, titleSize: 0))
                x = frame.maxX + gap
            }
            y += row.height + gap
        }
        return ShareLayout(
            size: size, style: .mosaic, covers: covers, bands: [], labels: [], footerY: footerY,
            fact: content.mosaicFooter, appName: ShareFonts.appName, bigNumber: "\(content.total)",
            heading: content.heading, headerTop: headerTop)
    }
}

// MARK: - 題名の折り返し

/// 表紙の下の題名（2行まで）。「の」「・」「「」などの切れ目で折り返し、入らなければ小さく→「…」（design-brief §7）
enum ShareTitle {
    /// この文字のあとで折り返してよい（「の」「・」と、助詞・区切りの記号）
    private static let breakAfter: Set<Character> = [
        "の", "・", "を", "と", "に", "は", "が", "へ", "で", "も", "、", "：", ":", " ", "　", "―", "-",
    ]
    /// この文字の前で折り返してよい
    private static let breakBefore: Set<Character> = ["「", "『", "（", "(", "〈", "《"]

    @MainActor
    static func lines(
        _ title: String, size base: CGFloat, width: CGFloat, measure: ShareLayoutEngine.Measure
    ) -> (lines: [String], size: CGFloat) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ([], base) }
        let minimum = (base * 0.72).rounded()
        var size = base
        while size >= minimum {
            if measure(text, size) <= width { return ([text], size) }
            if let pair = split(text, size: size, width: width, measure: measure) { return (pair, size) }
            size -= 2
        }
        // 切れ目で収まらない: 1行目に入るだけ入れ、残りを2行目に（入らなければ「…」）
        size = minimum
        let characters = Array(text)
        var cut = characters.count
        while cut > 1, measure(String(characters[..<cut]), size) > width { cut -= 1 }
        let first = String(characters[..<cut])
        var rest = String(characters[cut...])
        if rest.isEmpty { return ([first], size) }
        if measure(rest, size) > width {
            var restChars = Array(rest)
            while restChars.count > 1, measure(String(restChars) + "…", size) > width { restChars.removeLast() }
            rest = String(restChars) + "…"
        }
        return ([first, rest], size)
    }

    /// 切れ目のうち、2行の長いほうがいちばん短くなる所で2行に分ける（どちらも幅に収まるときだけ）
    @MainActor
    private static func split(
        _ text: String, size: CGFloat, width: CGFloat, measure: ShareLayoutEngine.Measure
    ) -> [String]? {
        let characters = Array(text)
        var best: (lines: [String], longest: CGFloat)?
        for index in 1..<characters.count {
            let canBreak = breakAfter.contains(characters[index - 1]) || breakBefore.contains(characters[index])
            guard canBreak else { continue }
            let first = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            let second = String(characters[index...]).trimmingCharacters(in: .whitespaces)
            guard !first.isEmpty, !second.isEmpty else { continue }
            let longest = max(measure(first, size), measure(second, size))
            if longest <= width, longest < (best?.longest ?? .infinity) {
                best = ([first, second], longest)
            }
        }
        return best?.lines
    }
}

// MARK: - 書体と色

/// 共有画像の書体・色・アプリ名（design-brief §7。アプリ本体の白黒の決まりの例外）
enum ShareFonts {
    /// 右下に小さく入れるアプリ名（F8-4。翻訳しない）
    static let appName = "local-bookshelf"

    static let background = Color(red: 0xEF / 255, green: 0xEA / 255, blue: 0xE3 / 255)
    static let band = Color(red: 0xDC / 255, green: 0xD6 / 255, blue: 0xCE / 255)
    static let text = Color(red: 0x1E / 255, green: 0x1B / 255, blue: 0x18 / 255)
    static let accent = Color(red: 0x5B / 255, green: 0x8A / 255, blue: 0x72 / 255)
    static let note = Color(red: 0x8A / 255, green: 0x80 / 255, blue: 0x77 / 255)

    /// Noto Serif JP（共有画像の題名は 700）。画像は決まった大きさなので Dynamic Type には合わせない
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Noto Serif JP", fixedSize: size).weight(weight)
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Noto Sans JP", fixedSize: size).weight(weight)
    }

    /// 題名の幅を測る（Noto Serif JP 700。書体が無いときは同じ太さのシステムの書体）
    @MainActor
    static func titleWidth(_ text: String, _ size: CGFloat) -> CGFloat {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Noto Serif JP",
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        return (text as NSString).size(withAttributes: [.font: font, .kern: size * 0.02]).width.rounded(.up)
    }
}

// MARK: - 画像の生成

/// 生成した共有画像（JPEG。位置情報などのメタデータは持たない。S6）
struct ShareImage: @unchecked Sendable {
    let data: Data
    let image: UIImage
    let format: ShareFormat
}

enum ShareRenderError: Error {
    case renderFailed
    case encodeFailed
}

/// 共有画像を端末の中で作る（通信なし。F8-3・S1）。表紙はサムネイルを使い、ImageRenderer で 1080 幅に描く
enum ShareRenderer {
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Share")

    @MainActor
    static func render(_ content: ShareContent, format: ShareFormat, images: ImageStore) async throws -> ShareImage {
        let covers = await loadCovers(content.books.map(\.id), images: images)
        return try render(content, format: format, covers: covers)
    }

    /// 読み込み済みの表紙で描く
    @MainActor
    static func render(_ content: ShareContent, format: ShareFormat, covers: [UUID: UIImage]) throws -> ShareImage {
        var aspects: [UUID: CGFloat] = [:]
        for (id, image) in covers where image.size.height > 0 {
            aspects[id] = image.size.width / image.size.height
        }
        let layout = ShareLayoutEngine.layout(content, format: format, aspects: aspects)
        let renderer = ImageRenderer(content: ShareTemplateView(layout: layout, covers: covers))
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(layout.size)
        guard let cgImage = renderer.cgImage else {
            logger.error("共有画像を描けない")
            throw ShareRenderError.renderFailed
        }
        let image = UIImage(cgImage: cgImage)
        // UIImage から書き出すので、元の写真の EXIF・位置情報は入らない（S6）
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            logger.error("共有画像を JPEG にできない")
            throw ShareRenderError.encodeFailed
        }
        return ShareImage(data: data, image: image, format: format)
    }

    /// 表紙のサムネイルを並行して読む（読めない本は無地の枠で描く）
    @MainActor
    static func loadCovers(_ ids: [UUID], images: ImageStore) async -> [UUID: UIImage] {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for id in ids {
                let url = images.thumbnailURL(for: id)
                group.addTask { (id, await CoverImageCache.decode(url)) }
            }
            var result: [UUID: UIImage] = [:]
            for await (id, image) in group {
                if let image {
                    result[id] = image
                } else {
                    logger.error("共有画像の表紙を読めない: \(id.uuidString, privacy: .public)")
                }
            }
            return result
        }
    }
}
