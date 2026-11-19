import Foundation
import Testing

@testable import Bookshelf

/// 言語の設定（設定の「言語」）。AppleLanguages への書き込みと、その場での言語の切り替え（AppLocale）
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
        let settings = LanguageSettings(defaults: makeDefaults(), current: "ja", apply: record)
        #expect(settings.language == .system)
    }

    @Test func choosingALanguageWritesAppleLanguagesAndAsksToRelaunch() {
        let defaults = makeDefaults()
        let settings = LanguageSettings(defaults: defaults, current: "ja", apply: record)
        settings.language = .english
        #expect(stored(defaults, LanguageSettings.appleLanguagesKey) as? [String] == ["en"])

        // 開き直したあと: 英語で起動し、English が選ばれていて、開き直しは不要
        let relaunched = LanguageSettings(defaults: defaults, current: "en", apply: record)
        #expect(relaunched.language == .english)
    }

    @Test func systemRemovesTheOverride() {
        let defaults = makeDefaults()
        let settings = LanguageSettings(defaults: defaults, current: "ja", apply: record)
        settings.language = .japanese
        settings.language = .system
        #expect(stored(defaults, LanguageSettings.appleLanguagesKey) == nil)
    }

    /// アプリに反映する言語を記録する（AppLocale は変えない。ほかのテストと同時に走るため）
    private let applied = Applied()
    private var record: (String?) -> Void { { [applied] in applied.values.append($0) } }

    final class Applied: @unchecked Sendable {
        var values: [String?] = []
    }

    /// 選ぶとその場で反映する（起動時の言語 → English → システム）
    @Test func appliesTheLanguageImmediately() {
        let settings = LanguageSettings(defaults: makeDefaults(), current: "ja", apply: record)
        settings.language = .english
        settings.language = .system
        #expect(applied.values == [nil, "en", nil])
    }

    /// 選んだ言語で文言・日付の言語が決まる（String(appLocalized:)・displaysInEnglish）
    @Test func textFollowsTheChosenLanguage() {
        AppLocale.$override.withValue("en") {
            #expect(String(appLocalized: "外観") == "Appearance")
            #expect(String(appLocalized: "\(3)件") == "3")
            #expect(InitialGenres.displaysInEnglish)
        }
        AppLocale.$override.withValue("ja") {
            #expect(String(appLocalized: "外観") == "外観")
            #expect(String(appLocalized: "\(3)件") == "3件")
            #expect(!InitialGenres.displaysInEnglish)
        }
    }

    /// iOS の設定アプリで App の言語を変えたときは、いま使っている言語を選んだことにする
    @Test func followsTheLanguageChangedInTheSettingsApp() {
        let defaults = makeDefaults()
        LanguageSettings(defaults: defaults, current: "ja", apply: record).language = .english
        let relaunched = LanguageSettings(defaults: defaults, current: "ja", apply: record)
        #expect(relaunched.language == .japanese)
    }
}
