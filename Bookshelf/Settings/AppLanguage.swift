import Foundation
import SwiftData
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

/// 言語の設定を保存し、その場でアプリの言語を切り替える（AppLocale）。
/// あわせて iOS の「App ごとの言語」と同じ AppleLanguages にも書く（次に開いたときのカメラの許可の説明など、
/// iOS が出す文言もそろえるため）
@MainActor
@Observable
final class LanguageSettings {
    static let key = "settings.language"
    static let appleLanguagesKey = "AppleLanguages"
    @ObservationIgnored private let defaults: UserDefaults
    /// 選んだ言語をアプリに反映する（ふつうは AppLocale.set。テストでは何もしないものを渡し、ほかのテストの文言を変えない）
    @ObservationIgnored private let apply: (String?) -> Void

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Self.key)
            if let languages = language.appleLanguages {
                defaults.set(languages, forKey: Self.appleLanguagesKey)
            } else {
                defaults.removeObject(forKey: Self.appleLanguagesKey)
            }
            apply(language.appleLanguages?.first)
            restoresBrowse = true
            revision += 1
        }
    }

    /// 言語を変えるたびに増える。アプリの画面をこの値で作り直し、すべての文言を新しい言語にする
    private(set) var revision = 0

    /// 作り直したあと、閲覧画面を前の状態（見ていた棚・見え方・まとめ方）に戻し、設定を開き直す
    @ObservationIgnored var restoresBrowse = false
    /// 閲覧画面の今の状態（閲覧画面が変わるたびに書く）
    @ObservationIgnored var browse: BrowseSnapshot?

    /// - Parameter current: いま使っている言語（Bundle の preferredLocalizations の先頭）。
    ///   保存した言語と違うとき（iOS の設定アプリで App の言語を変えたとき）は、いまの言語を選んだことにする
    init(
        defaults: UserDefaults, current: String? = Bundle.main.preferredLocalizations.first,
        apply: @escaping (String?) -> Void = AppLocale.set
    ) {
        self.defaults = defaults
        self.apply = apply
        var saved = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
        if saved != .system, let current, current != saved.rawValue {
            saved = AppLanguage(rawValue: current) ?? .system
        }
        language = saved
        apply(saved.appleLanguages?.first)
    }
}

/// 言語を変えて画面を作り直すときに、閲覧画面を戻すための状態
struct BrowseSnapshot: Equatable {
    var shelfID: PersistentIdentifier?
    var mode: DisplayMode
    var grouping: BrowseGrouping
    var monthPeriod: PurchasePeriod
}
