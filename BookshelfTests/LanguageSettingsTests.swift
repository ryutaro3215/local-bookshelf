import Foundation
import Testing

@testable import Bookshelf

/// 言語の設定（設定の「言語」）。AppleLanguages への書き込みと、開き直しが要るかどうか
@MainActor
struct LanguageSettingsTests {
    private let suite = "LanguageSettingsTests.\(UUID().uuidString)"

    private func makeDefaults() -> UserDefaults {
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    /// この設定の保存先だけに書かれた値（端末全体の AppleLanguages は含めない）
    private func stored(_ defaults: UserDefaults, _ key: String) -> Any? {
        defaults.persistentDomain(forName: suite)?[key]
    }

    @Test func defaultsToSystemWithoutRelaunch() {
        let settings = LanguageSettings(defaults: makeDefaults(), current: "ja")
        #expect(settings.language == .system)
        #expect(!settings.needsRelaunch)
    }

    @Test func choosingALanguageWritesAppleLanguagesAndAsksToRelaunch() {
        let defaults = makeDefaults()
        let settings = LanguageSettings(defaults: defaults, current: "ja")
        settings.language = .english
        #expect(stored(defaults, LanguageSettings.appleLanguagesKey) as? [String] == ["en"])
        #expect(settings.needsRelaunch)

        // 開き直したあと: 英語で起動し、English が選ばれていて、開き直しは不要
        let relaunched = LanguageSettings(defaults: defaults, current: "en")
        #expect(relaunched.language == .english)
        #expect(!relaunched.needsRelaunch)
    }

    @Test func systemRemovesTheOverride() {
        let defaults = makeDefaults()
        let settings = LanguageSettings(defaults: defaults, current: "ja")
        settings.language = .japanese
        settings.language = .system
        #expect(stored(defaults, LanguageSettings.appleLanguagesKey) == nil)
        #expect(!settings.needsRelaunch)
    }

    /// iOS の設定アプリで App の言語を変えたときは、いま使っている言語を選んだことにする
    @Test func followsTheLanguageChangedInTheSettingsApp() {
        let defaults = makeDefaults()
        LanguageSettings(defaults: defaults, current: "ja").language = .english
        let relaunched = LanguageSettings(defaults: defaults, current: "ja")
        #expect(relaunched.language == .japanese)
    }
}
