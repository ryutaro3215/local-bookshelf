import SwiftUI
import UIKit

/// 外観（設定の「外観」。2026-11-19 オーナー指示）。システムに合わせる・ライト・ダーク
nonisolated enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .system: "システムに合わせる"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    /// ウインドウに付ける外観（system は端末の設定に従う）
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 外観の設定を保存し、アプリのすべてのウインドウ（シート・UIKit の部品を含む）に反映する
@MainActor
@Observable
final class AppearanceSettings {
    static let key = "settings.appearance"
    @ObservationIgnored private let defaults: UserDefaults

    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Self.key)
            apply()
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.key).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// 開いているウインドウすべてに外観を付ける（SwiftUI の preferredColorScheme は「システムに合わせる」に戻せないことがあるため）
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = appearance.interfaceStyle
            }
        }
    }
}
