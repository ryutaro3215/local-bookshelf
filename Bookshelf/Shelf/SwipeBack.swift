import UIKit

// MARK: - 画面の左端からの右スワイプで戻る

/// 戻る先がある画面（設定・本の詳細・ジャンル管理など）で、画面の左端から右へスワイプして戻れるようにする。
/// どの画面もナビゲーションバーを隠して自前の「‹ 戻る」を出しているため、iOS 標準の左端スワイプが止まっている。
/// その標準のジェスチャをもう一度使えるようにする（いちばん最初の画面＝本棚では動かさない）
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        // 戻る先があり、画面が切り替わる途中でないときだけ
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}
