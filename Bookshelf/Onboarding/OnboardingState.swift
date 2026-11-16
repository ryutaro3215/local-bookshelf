import Foundation
import SwiftData
import os

/// 初回チュートリアルを終えたか（requirements F1-7）。最初の1冊を登録したら終わり、2回目以降の起動では出さない。
/// 途中でアプリを閉じたときは、次の起動でもう一度チュートリアルから始める（登録は必須でスキップしない）
@MainActor
@Observable
final class OnboardingState {
    static let completedKey = "onboarding.completed"
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Onboarding")

    private(set) var isCompleted: Bool
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter hasBooks: すでに本がある（以前の版で登録済みなど）ならチュートリアルは出さない
    init(defaults: UserDefaults, hasBooks: Bool) {
        self.defaults = defaults
        isCompleted = defaults.bool(forKey: Self.completedKey) || hasBooks
    }

    /// 最初の1冊を登録した
    func complete() {
        defaults.set(true, forKey: Self.completedKey)
        isCompleted = true
    }

    /// アプリの環境から作る。
    /// UIテスト（デバッグビルドの `-UITestReset`・`-UITestPersistentStore`）では、既存のテストが止まらないように
    /// チュートリアルを飛ばす。チュートリアル自体を確かめるときは `-UITestOnboarding` も付ける
    static func make(environment: AppEnvironment, arguments: [String] = ProcessInfo.processInfo.arguments)
        -> OnboardingState
    {
        var count = 0
        do {
            count = try environment.store.context.fetchCount(FetchDescriptor<Book>())
        } catch {
            // 数えられないときは本が無いものとして扱う（チュートリアルの終了の記録があればそちらで判断される）
            Self.logger.error("本の数を数えられない: \(error.localizedDescription, privacy: .public)")
        }
        let state = OnboardingState(defaults: environment.recent.defaults, hasBooks: count > 0)
        #if DEBUG
            let isUITest = arguments.contains("-UITestReset") || arguments.contains("-UITestPersistentStore")
            if isUITest && !arguments.contains("-UITestOnboarding") {
                state.isCompleted = true
            }
        #endif
        return state
    }
}
