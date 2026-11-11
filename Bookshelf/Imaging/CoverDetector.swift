import CoreGraphics
import CoreVideo
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

    /// 左上から時計回りの4点
    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// 画像の各辺から inset（割合）だけ内側に置いた四隅。検出に失敗したときの手動調整の初期値（F1-2・N 画面）
    static func inset(_ inset: CGFloat) -> CoverQuad {
        let lo = inset
        let hi = 1 - inset
        return CoverQuad(
            topLeft: CGPoint(x: lo, y: hi), topRight: CGPoint(x: hi, y: hi),
            bottomRight: CGPoint(x: hi, y: lo), bottomLeft: CGPoint(x: lo, y: lo))
    }
}

/// 撮影画像から表紙（本の表紙らしい四角形）の四隅を端末内で検出する（requirements F1-2）。
///
/// T5 で検出を改善した（実写25枚で 6/25 → 下記の組み合わせ。build-log T5 に記録）:
/// 1. `VNDetectDocumentSegmentationRequest`（書類・カードなど「手に持った平らな物」の輪郭を機械学習で取る）を主に使う。
///    手・背景の本棚・帯に強い
/// 2. 書類の輪郭の近くに `VNDetectRectanglesRequest` の四角形があれば、その四角形に寄せる（辺がより正確）
/// 3. 書類の輪郭が表紙らしくない形（縦横比・角度・大きさ）のときは、従来の四角形検出（大きいものだけ）に戻る
nonisolated struct CoverDetector: Sendable {
    /// 表紙の短辺/長辺の比の範囲。文庫（約0.69）・新書（約0.56）・正方形に近い絵本まで含める
    var minimumAspectRatio: Float = 0.4
    var maximumAspectRatio: Float = 1.0
    /// 四角形検出だけで決めるときの、画像の短辺に対する表紙の最小の大きさ。
    /// 表紙の内側の四角形（帯・絵・文字の枠）を拾わないよう大きめにする
    var minimumSize: Float = 0.4
    /// 書類の輪郭に寄せるための四角形の最小の大きさ（寄せる相手は書類の輪郭の近くに限るので小さくてよい）
    var snapMinimumSize: Float = 0.2
    /// 角の直角からのずれの許容（度）。斜めから撮った台形を受け入れる
    var quadratureTolerance: Float = 30
    var minimumConfidence: Float = 0.6
    /// 書類の輪郭を採用する最低の信頼度
    var minimumDocumentConfidence: Float = 0.5
    /// 書類の輪郭が画像に占める最小の面積（小さすぎるものは表紙を枠に入れていないとみなす）
    var minimumDocumentArea: CGFloat = 0.08
    /// 四角形を書類の輪郭に寄せるときの、各頂点の距離の上限（正規化座標）
    var snapDistance: CGFloat = 0.05

    /// 四隅を返す。見つからなければ nil。画像は上向き（orientation .up）で渡す
    func detect(in image: CGImage) throws -> CoverQuad? {
        try detect(
            handler: VNImageRequestHandler(cgImage: image, orientation: .up), width: image.width, height: image.height)
    }

    /// カメラの映像の1コマから四隅を返す（ファインダーの上に検出結果を描くため）。
    /// コマは上向き（orientation .up）にそろえて渡す
    func detect(in buffer: CVPixelBuffer) throws -> CoverQuad? {
        try detect(
            handler: VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }

    private func detect(handler: VNImageRequestHandler, width: Int, height: Int) throws -> CoverQuad? {
        let document = VNDetectDocumentSegmentationRequest()
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = minimumAspectRatio
        rectangles.maximumAspectRatio = maximumAspectRatio
        rectangles.minimumSize = min(minimumSize, snapMinimumSize)
        rectangles.quadratureTolerance = quadratureTolerance
        rectangles.minimumConfidence = minimumConfidence
        rectangles.maximumObservations = 10

        // 注意: 書類の輪郭の検出は内部で Swift Concurrency の協調スレッドを使う。協調スレッドから同期的に
        // 多数を同時に呼ぶとスレッドが尽きて止まる（シミュレータで、並列のテストから10件同時に呼んで再現）。
        // アプリでは CoverPipeline（actor）で1枚ずつ呼び、ライブの検出は GCD のキューから呼ぶので起きない
        try handler.perform([document, rectangles])

        let aspect = CGFloat(width) / CGFloat(max(height, 1))
        let boxes = (rectangles.results ?? []).map(Self.quad(from:))

        if let observation = document.results?.first, observation.confidence >= minimumDocumentConfidence {
            let outline = Self.quad(from: observation)
            if isCoverShaped(outline, imageAspect: aspect) {
                // 書類の輪郭の近くにある四角形のうち、一番近いものに寄せる
                let near = boxes.filter { maxCornerDistance($0, outline) <= snapDistance }
                if let snapped = near.min(by: { maxCornerDistance($0, outline) < maxCornerDistance($1, outline) }) {
                    return snapped
                }
                return outline
            }
        }

        // 書類の輪郭が使えないときは、T3 と同じ強さの四角形検出に戻る: 短い方の辺が画像の短辺の minimumSize 以上で、
        // 縦長（縦持ちで撮る表紙の形）のものだけを候補にし、一番大きいものを選ぶ。
        // 表紙の内側の横長の帯・絵の枠を「検出成功」にするより、検出失敗（N 画面で手動調整）の方がよい
        let large = boxes.filter { isLargePortraitRectangle($0, imageAspect: aspect) }
        guard let best = large.max(by: { Self.area($0) < Self.area($1) }) else {
            return nil
        }
        return best
    }

    /// 四角形の幅と高さ（ピクセルの比。正規化座標の x に画像の縦横比を掛けて単位をそろえる。高さ1＝画像の高さ）
    func size(of q: CoverQuad, imageAspect: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let p = q.points.map { CGPoint(x: $0.x * imageAspect, y: $0.y) }
        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        let width = (length(p[0], p[1]) + length(p[2], p[3])) / 2
        let height = (length(p[1], p[2]) + length(p[3], p[0])) / 2
        return (width, height)
    }

    /// 縦長か（高さ ≧ 幅 × 0.95。正方形に近い絵本まで許し、横長の帯・枠は除く）
    func isPortrait(_ q: CoverQuad, imageAspect: CGFloat) -> Bool {
        let s = size(of: q, imageAspect: imageAspect)
        return s.width > 0 && s.height >= s.width * 0.95
    }

    /// 四角形検出だけで決めるときの条件（大きさ・縦長・凸）
    func isLargePortraitRectangle(_ q: CoverQuad, imageAspect: CGFloat) -> Bool {
        let s = size(of: q, imageAspect: imageAspect)
        let shortSide = min(imageAspect, 1)
        guard min(s.width, s.height) >= CGFloat(minimumSize) * shortSide else { return false }
        guard isPortrait(q, imageAspect: imageAspect) else { return false }
        return Self.isConvex(q.points)
    }

    /// 書類の輪郭が表紙らしい形か（凸・大きさ・縦横比・角度）
    func isCoverShaped(_ q: CoverQuad, imageAspect: CGFloat) -> Bool {
        // 縦横比の計算はピクセルの比で行う（正規化座標は縦横で長さの単位が違う）
        let p = q.points.map { CGPoint(x: $0.x * imageAspect, y: $0.y) }
        guard Self.isConvex(p) else { return false }
        guard Self.area(q) >= minimumDocumentArea else { return false }
        // 画像全体をそのまま返したもの（検出できなかったときの Vision の返し方）は採用しない
        let full = CoverQuad.inset(0)
        if maxCornerDistance(q, full) < 0.01 { return false }
        // 画像の3辺以上に貼りついた輪郭（画像の端から端までの帯など）は、手に持った表紙ではない
        let edge: CGFloat = 0.015
        let touches = [
            q.points.filter { $0.x <= edge }.count >= 2, q.points.filter { $0.x >= 1 - edge }.count >= 2,
            q.points.filter { $0.y <= edge }.count >= 2, q.points.filter { $0.y >= 1 - edge }.count >= 2,
        ].filter { $0 }.count
        if touches >= 3 { return false }

        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        let top = length(p[0], p[1])
        let right = length(p[1], p[2])
        let bottom = length(p[2], p[3])
        let left = length(p[3], p[0])
        let width = (top + bottom) / 2
        let height = (left + right) / 2
        guard width > 0, height > 0 else { return false }
        // 縦持ちで撮る表紙は縦長。横長の輪郭（シミュレータの「下端の帯」など）は採用しない
        guard height >= width * 0.95 else { return false }
        let ratio = Float(min(width, height) / max(width, height))
        guard ratio >= minimumAspectRatio, ratio <= maximumAspectRatio else { return false }
        // 向かい合う辺の長さが極端に違うもの（ゆがんだ輪郭）は表紙ではない
        guard min(top, bottom) / max(top, bottom) >= 0.6, min(left, right) / max(left, right) >= 0.6 else {
            return false
        }
        // 各角が直角から quadratureTolerance＋5度以内
        for i in 0..<4 {
            let a = p[(i + 3) % 4]
            let b = p[i]
            let c = p[(i + 1) % 4]
            let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
            let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
            let cosine = (v1.x * v2.x + v1.y * v2.y) / (hypot(v1.x, v1.y) * hypot(v2.x, v2.y))
            let degrees = acos(max(-1, min(1, cosine))) * 180 / .pi
            if abs(degrees - 90) > CGFloat(quadratureTolerance) + 5 { return false }
        }
        return true
    }

    /// 2つの四角形の対応する頂点の距離の最大
    func maxCornerDistance(_ a: CoverQuad, _ b: CoverQuad) -> CGFloat {
        zip(a.points, b.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? .infinity
    }

    static func quad(from r: VNRectangleObservation) -> CoverQuad {
        CoverQuad(topLeft: r.topLeft, topRight: r.topRight, bottomRight: r.bottomRight, bottomLeft: r.bottomLeft)
    }

    /// 四角形の面積（正規化座標。靴ひも公式）
    static func area(_ q: CoverQuad) -> CGFloat {
        let p = q.points
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i]
            let b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// 4点が凸の四角形をなすか（外積の符号がそろう）
    static func isConvex(_ p: [CGPoint]) -> Bool {
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = p[i]
            let b = p[(i + 1) % 4]
            let c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross == 0 { return false }
            if sign == 0 {
                sign = cross
            } else if (sign > 0) != (cross > 0) {
                return false
            }
        }
        return true
    }
}
