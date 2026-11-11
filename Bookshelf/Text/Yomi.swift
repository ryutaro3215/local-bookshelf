import CoreFoundation
import Foundation

/// 題名から「よみ」（ひらがな）を端末内で作る（requirements N7・F7-1）。
/// 通信はしない。人名・難読語は誤ることがある（requirements の割り切り）。
enum Yomi {
    /// 例: 「存在と時間」→「そんざいとじかん」。英字・数字はそのまま残す。
    static func make(from title: String) -> String {
        let text = title as CFString
        let length = CFStringGetLength(text)
        guard length > 0 else { return "" }

        let locale = CFLocaleCreate(kCFAllocatorDefault, CFLocaleIdentifier("ja" as CFString))
        guard
            let tokenizer = CFStringTokenizerCreate(
                kCFAllocatorDefault, text, CFRangeMake(0, length), kCFStringTokenizerUnitWordBoundary, locale)
        else {
            return katakanaToHiragana(title)
        }

        var result = ""
        var cursor = 0
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while tokenType != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // トークンの間にある文字（空白・記号など）はそのまま残す
            if range.location > cursor {
                result += substring(title, CFRangeMake(cursor, range.location - cursor))
            }
            let token = substring(title, range)
            result += reading(of: token, tokenizer: tokenizer)
            cursor = range.location + range.length
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        if cursor < length {
            result += substring(title, CFRangeMake(cursor, length - cursor))
        }
        return result
    }

    /// 1トークン分のよみ。英字・数字だけのトークンはそのまま返す。
    private static func reading(of token: String, tokenizer: CFStringTokenizer) -> String {
        if token.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return token
        }
        // かな（ひらがな・カタカナ・長音）だけのトークンは、ローマ字を経由せずにひらがなにする（長音を保つため）
        if token.unicodeScalars.allSatisfy({ (0x3040...0x30FF).contains($0.value) }) {
            return katakanaToHiragana(token)
        }
        let attribute = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription)
        guard let latin = attribute as? String else {
            return katakanaToHiragana(token)
        }
        let mutable = NSMutableString(string: latin) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return mutable as String
    }

    /// カタカナ（ァ〜ヶ）をひらがな（ぁ〜ゖ）にずらす。長音「ー」などはそのまま残す
    private static func katakanaToHiragana(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value), let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(hiragana)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func substring(_ text: String, _ range: CFRange) -> String {
        let ns = text as NSString
        return ns.substring(with: NSRange(location: range.location, length: range.length))
    }
}
