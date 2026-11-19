import Foundation
import SwiftUI

/// アプリの言語（設定の「言語」。2026-11-19 オーナー指示）。システムに合わせる・日本語・English
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    /// 一覧に出す名前。言語名はその言語自身で書く（どちらの言語で表示していても読めるように）
    var label: Text {
        switch self {
        case .system: Text("システムに合わせる")
        case .japanese: Text(verbatim: "日本語")
        case .english: Text(verbatim: "English")
        }
    }

    /// アプリだけの言語の指定（AppleLanguages）。system は指定を消して端末の言語に従う
    var appleLanguages: [String]? {
        self == .system ? nil : [rawValue]
    }
}

/// 言語の設定を保存する。iOS の「App ごとの言語」と同じく AppleLanguages に書き、次に開いたときから切り替わる
/// （画面の文言・日付の書式・カメラの許可の説明まで、すべてを同じ言語にそろえるため）
@MainActor
@Observable
final class LanguageSettings {
    static let key = "settings.language"
    static let appleLanguagesKey = "AppleLanguages"
    @ObservationIgnored private let defaults: UserDefaults
    /// 起動したときの言語（いま画面に出ている言語）
    let launchedLanguage: AppLanguage

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.key)
            if let languages = language.appleLanguages {
                defaults.set(languages, forKey: Self.appleLanguagesKey)
            } else {
                defaults.removeObject(forKey: Self.appleLanguagesKey)
            }
        }
    }

    /// 選んだ言語が、いま出ている言語と違う（開き直すと切り替わる）
    var needsRelaunch: Bool { language != launchedLanguage }

    /// - Parameter current: いま使っている言語（Bundle の preferredLocalizations の先頭）。
    ///   保存した言語と違うとき（iOS の設定アプリで App の言語を変えたとき）は、いまの言語を選んだことにする
    init(defaults: UserDefaults, current: String? = Bundle.main.preferredLocalizations.first) {
        self.defaults = defaults
        var saved = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
        if saved != .system, let current, current != saved.rawValue {
            saved = AppLanguage(rawValue: current) ?? .system
        }
        launchedLanguage = saved
        language = saved
    }
}
