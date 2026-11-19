import Foundation

/// 題名・ジャンル名の文字の整え方（requirements S6）。OCR の候補（TitleRecognizer）と保存（LibraryStore）で同じものを使う（N-028）
nonisolated enum TextSanitizer {
    /// 題名・ジャンル名の上限（S6）
    static let maxLength = 200

    /// 制御文字を除き、前後の空白を落として、200文字までに切り詰める
    static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxLength))
    }
}
