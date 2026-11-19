import SwiftUI
import UIKit

/// 書影の下（題名・購入日・位置）での横スワイプで、前後の本へめくる（2026-11-20 オーナー指示）。
/// 左へスワイプ = 次の本（+1）、右へスワイプ = 前の本（-1）。
/// はっきり横向きに動き出したときだけ始まる UIKit のパン（縦に動き出したら始まらない）なので、
/// 外側の縦のスクロール（棚をかえる）を邪魔しない。SwiftUI の DragGesture は simultaneousGesture でも
/// 外側の ScrollView のスクロールを止めてしまうため使わない
struct BookSwipeGesture: UIGestureRecognizerRepresentable {
    /// 長押しで選んでいる間・スクラバーを動かしている間は止める
    let isEnabled: Bool
    let onStep: (Int) -> Void

    /// 横に動いたとみなす量（指を離した位置）と、勢い（pt/秒）
    static let distance: CGFloat = 40
    static let velocity: CGFloat = 300
    /// 横の動きが縦の何倍以上なら横向きとみなすか
    static let dominance: CGFloat = 1.5

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended, let view = recognizer.view else { return }
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)
        if let step = Self.step(translation: translation, velocity: velocity) {
            onStep(step)
        }
    }

    /// 指を離したときの動きから、めくる向きを決める（横向きでなければ nil）
    static func step(translation: CGPoint, velocity: CGPoint) -> Int? {
        let dx = translation.x
        guard abs(dx) > abs(translation.y) * dominance else { return nil }
        if dx <= -distance || (dx < 0 && velocity.x <= -Self.velocity) { return 1 }
        if dx >= distance || (dx > 0 && velocity.x >= Self.velocity) { return -1 }
        return nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// はっきり横向きに動き出したときだけ始める（縦なら外側のスクロールに任せる）
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * BookSwipeGesture.dominance
        }

        /// 押したときの操作（選択の解除）などと一緒に動く
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

extension View {
    /// 横スワイプで前後の本へめくる（`BookSwipeGesture`）
    func bookSwipe(isEnabled: Bool, onStep: @escaping (Int) -> Void) -> some View {
        gesture(BookSwipeGesture(isEnabled: isEnabled, onStep: onStep))
    }
}
