import CoreGraphics
import Foundation
import ImageIO
import Vision
import os

/// OCR で読み取った1行（縦書きなら1列）の文字列と、題名らしさを決める手がかり
nonisolated struct RecognizedLine: Sendable, Equatable {
    var text: String
    /// 文字の大きさ（行の短い方の辺。ピクセル）。題名は表紙でいちばん大きい文字であることが多い
    var characterSize: Double
    /// 行を囲む矩形（ピクセル座標・原点は左上）
    var frame: CGRect
    /// Vision が見出し（題名）らしいと判定した行
    var isTitle: Bool = false

    /// 縦書きの列（縦に長い行）
    var isVertical: Bool { frame.height > frame.width * 1.2 && text.count > 1 }
}

/// 表紙画像から題名の候補を端末内の文字認識（Vision）で取り出す（requirements F2-2〜F2-4）。
/// 通信はしない。認識に失敗しても投げずに空の候補を返す（登録の操作を止めない）
nonisolated struct TitleRecognizer: Sendable {
    /// 候補の最大数（題名欄で選べる数）
    static let maxCandidates = 5
    /// 日本語（縦書き・横書き）と英語
    static let languages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
    /// 認識に使う画像の長辺の上限（処理時間とメモリを抑える）
    static let workingLongSide = 2048
    /// 候補の文字数の上限（requirements S6 の題名の上限と同じ）
    static let maxLength = 200

    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "TitleRecognizer")

    /// 画像データ（JPEG・HEIC など）から題名の候補を返す。題名らしい順。読めなければ空。
    /// `@concurrent`: 画面（MainActor）から呼んでも、画像のデコードと並べ替えはバックグラウンドで動く（N-025・F2-2）
    @concurrent
    func candidates(in data: Data) async -> [String] {
        guard let image = Self.uprightImage(from: data) else {
            Self.logger.error("題名の認識: 画像を読み込めなかった")
            return []
        }
        return await candidates(in: image)
    }

    /// 上向き（orientation .up）の画像から題名の候補を返す。題名らしい順。読めなければ空
    @concurrent
    func candidates(in image: CGImage) async -> [String] {
        do {
            let lines = try await recognizeLines(in: image)
            return Self.rankCandidates(lines)
        } catch {
            Self.logger.error("題名の認識に失敗: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 画像の中の文字を行ごとに読み取る
    func recognizeLines(in image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Self.languages
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image, orientation: .up)

        let width = Double(image.width)
        let height = Double(image.height)
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            // 正規化座標（原点は左下）→ ピクセル座標（原点は左上）
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                .map { CGPoint(x: $0.x * width, y: (1 - $0.y) * height) }
            func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
            let along = distance(corners[0], corners[1])
            let across = distance(corners[0], corners[3])
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            let frame = CGRect(
                x: xs.min() ?? 0, y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
            return RecognizedLine(
                text: best.string, characterSize: min(along, across), frame: frame, isTitle: observation.isTitle)
        }
    }

    // MARK: - 題名らしい順に並べる

    /// Vision が見出しと判定した行の重み（文字の大きさに掛ける）
    static let titleBoost = 1.5
    /// 同じ題名の続きとみなす行の文字の大きさの比
    static let mergeSizeRatio = 0.75
    /// 同じ題名の続きとみなす行の間隔（文字の大きさに対する比）
    static let mergeGapRatio = 0.8

    /// 読み取った行から題名の候補を作る。文字の大きい行ほど前に置き、
    /// 2行（縦書きは2列）にわたる題名は、つないだものを先に置く
    static func rankCandidates(_ lines: [RecognizedLine]) -> [String] {
        let usable = lines.compactMap { line -> RecognizedLine? in
            var line = line
            line.text = clean(line.text)
            return isPlausibleTitle(line.text) ? line : nil
        }
        func score(_ line: RecognizedLine) -> Double {
            line.characterSize * (line.isTitle ? titleBoost : 1)
        }
        let ranked = usable.sorted { score($0) > score($1) }

        var result: [String] = []
        func append(_ text: String) {
            let text = clean(text)
            guard isPlausibleTitle(text), !result.contains(text) else { return }
            result.append(text)
        }
        for line in ranked {
            let group = continuationGroup(of: line, in: usable)
            if group.count > 1 {
                append(group.map(\.text).joined())
            }
            append(line.text)
            if result.count >= maxCandidates { break }
        }
        return Array(result.prefix(maxCandidates))
    }

    /// line と同じ大きさ・同じ向きで隣り合う行をたどり、読む順（横書きは上から、縦書きは右から）に並べる
    static func continuationGroup(of line: RecognizedLine, in lines: [RecognizedLine]) -> [RecognizedLine] {
        var group = [line]
        var changed = true
        while changed {
            changed = false
            for candidate in lines where !group.contains(candidate) {
                if group.contains(where: { isContinuation($0, candidate) }) {
                    group.append(candidate)
                    changed = true
                }
            }
        }
        if line.isVertical {
            return group.sorted { $0.frame.midX > $1.frame.midX }
        }
        return group.sorted { $0.frame.midY < $1.frame.midY }
    }

    /// 2つの行が同じ題名の続き（文字の大きさが近く、向きが同じで、間が狭く、並びが重なる）か
    static func isContinuation(_ a: RecognizedLine, _ b: RecognizedLine) -> Bool {
        let small = min(a.characterSize, b.characterSize)
        let large = max(a.characterSize, b.characterSize)
        guard large > 0, small / large >= mergeSizeRatio, a.isVertical == b.isVertical else { return false }
        let maxGap = large * mergeGapRatio
        if a.isVertical {
            // 縦書き: 左右に並ぶ列。上下の範囲が重なる
            let gap = max(a.frame.minX, b.frame.minX) - min(a.frame.maxX, b.frame.maxX)
            let overlap = min(a.frame.maxY, b.frame.maxY) - max(a.frame.minY, b.frame.minY)
            return gap <= maxGap && overlap > 0
        }
        // 横書き: 上下に並ぶ行。左右の範囲が重なる
        let gap = max(a.frame.minY, b.frame.minY) - min(a.frame.maxY, b.frame.maxY)
        let overlap = min(a.frame.maxX, b.frame.maxX) - max(a.frame.minX, b.frame.minX)
        return gap <= maxGap && overlap > 0
    }

    /// 制御文字を除き、前後の空白を落として、200文字までに切り詰める（S6）
    static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxLength))
    }

    /// 題名になりうる文字列か（文字を含む。数字・記号だけの行〔価格・番号〕は除く）
    static func isPlausibleTitle(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    // MARK: - 画像の読み込み

    /// 向き（EXIF Orientation）を反映した上向きの画像を作る。大きすぎる画像は縮める
    static func uprightImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), workingLongSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
