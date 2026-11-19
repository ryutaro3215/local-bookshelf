import Foundation

/// いまアプリが表示に使っている言語と地域。設定の「言語」で選ぶと、その場で切り替わる。
/// アプリの文言は String(appLocalized:)（この言語の表から読む）、SwiftUI の Text はルートの環境の locale、
/// 日付は `locale` を使う。iOS の String(localized:) はアプリを開き直すまで言語が変わらないため、文言はこちらで読む
nonisolated enum AppLocale {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var chosen: String?

    /// 端末が選んだアプリの言語（起動したときの言語。設定で「システムに合わせる」を選んだときに使う）
    static let systemLanguage: String = Bundle.main.preferredLocalizations.first ?? "ja"

    /// 言語を決める（"ja"・"en"。nil は端末の言語）
    static func set(_ language: String?) {
        lock.lock()
        defer { lock.unlock() }
        chosen = language
    }

    /// テストで、ほかのテストに影響させずに言語を決める（そのタスクの中だけ）
    @TaskLocal static var override: String?

    /// いまの言語（"ja" か "en"）
    static var language: String {
        if let override { return override }
        lock.lock()
        defer { lock.unlock() }
        return chosen ?? systemLanguage
    }

    static var isEnglish: Bool { language.hasPrefix("en") }

    /// 文言・日付に使う locale。言語を選んだときは、その言語と端末の地域を組み合わせる
    static var locale: Locale {
        let language = self.language
        guard language != systemLanguage else { return .current }
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }
}

extension String {
    /// アプリの文言を、設定で選んだ言語で読む（String(localized:) の代わり。開き直さずに言語が変わる）
    nonisolated init(appLocalized resource: LocalizedStringResource) {
        var resource = resource
        resource.locale = AppLocale.locale
        self.init(localized: resource)
    }
}
