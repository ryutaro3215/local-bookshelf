import CoreGraphics
import Vision

/// 画像の中の表紙の四隅。座標は Vision と同じ正規化座標（0〜1、原点は左下）
nonisolated struct CoverQuad: Sendable, Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    /// 画像のピクセル座標（原点は左下。Core Image と同じ向き）に直す
    func pixelPoints(width: Int, height: Int) -> (
        topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint
    ) {
        func scale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * CGFloat(width), y: p.y * CGFloat(height))
        }
        return (scale(topLeft), scale(topRight), scale(bottomRight), scale(bottomLeft))
    }
}

/// 撮影画像から表紙（本の表紙らしい四角形）の四隅を端末内で検出する（requirements F1-2）
nonisolated struct CoverDetector: Sendable {
    /// 表紙の短辺/長辺の比の範囲。文庫（約0.69）・新書（約0.56）・正方形に近い絵本まで含める
    var minimumAspectRatio: Float = 0.4
    var maximumAspectRatio: Float = 1.0
    /// 画像の短辺に対する表紙の最小の大きさ。表紙の内側の四角形（帯・絵・文字の枠）を拾わないよう大きめにする。
    /// 誤った切り抜きより検出失敗（手動調整へ回す）の方がよい
    var minimumSize: Float = 0.4
    /// 角の直角からのずれの許容（度）。斜めから撮った台形を受け入れる
    var quadratureTolerance: Float = 30
    var minimumConfidence: Float = 0.6

    /// 四隅を返す。見つからなければ nil。画像は上向き（orientation .up）で渡す
    func detect(in image: CGImage) throws -> CoverQuad? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = minimumAspectRatio
        request.maximumAspectRatio = maximumAspectRatio
        request.minimumSize = minimumSize
        request.quadratureTolerance = quadratureTolerance
        request.minimumConfidence = minimumConfidence
        // 表紙の内側の四角形（帯・絵・文字の枠）を拾わないよう、候補を複数出して一番大きいものを選ぶ
        request.maximumObservations = 8

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        guard let best = request.results?.max(by: { area($0) < area($1) }) else {
            return nil
        }
        return CoverQuad(
            topLeft: best.topLeft, topRight: best.topRight,
            bottomRight: best.bottomRight, bottomLeft: best.bottomLeft)
    }

    /// 四角形の面積（正規化座標。靴ひも公式）
    private func area(_ r: VNRectangleObservation) -> CGFloat {
        let p = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i]
            let b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}
