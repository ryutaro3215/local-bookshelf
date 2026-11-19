import SwiftUI
import UIKit

/// 取り消しのトースト（棚の移動・購入）の出し方（N-062）。
/// VoiceOver を使っているときは、出したことを読み上げで知らせ、消えるまでの時間を延ばす（取り消すまでに指で探す時間が要るため）
enum ToastTiming {
    /// ふだんの表示時間（Figma・design-brief の 5 秒）
    static let standard: Duration = .seconds(5)
    /// VoiceOver を使っているときの表示時間
    static let voiceOver: Duration = .seconds(20)

    static var duration: Duration {
        #if DEBUG
            // UI テスト用: トーストが時間で消えないようにして、操作で消えることを確かめる（N-068①）
            if ProcessInfo.processInfo.arguments.contains("-UITestLongToast") { return .seconds(60) }
        #endif
        return UIAccessibility.isVoiceOverRunning ? voiceOver : standard
    }

    /// トーストの文言を読み上げる（取り消せるときはそのことも伝える）
    static func announce(_ message: String, canUndo: Bool) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let text = canUndo ? "\(message)。\(String(localized: "取り消す"))" : message
        AccessibilityNotification.Announcement(text).post()
    }
}
