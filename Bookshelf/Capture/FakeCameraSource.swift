#if DEBUG
    import SwiftUI
    import UIKit

    /// シミュレータ・UIテスト用のカメラ（シミュレータにはカメラが無い）。
    /// 架空の表紙を描いた合成画像を、シナリオの順に「撮影」する。実在の表紙は使わない。
    ///
    /// シナリオは起動引数 `-FakeCamera "cover:PAPER COMETS,blank,nocover"` で渡す（カンマ区切り。最後まで行くと先頭に戻る）
    /// - `cover:<題名>`: 机の上の、少し傾いた表紙（四隅を検出でき、題名を読める）
    /// - `blank`: 文字の無い表紙（四隅は検出できるが、題名の候補が出ない）
    /// - `nocover`: 表紙の無い画像（四隅を検出できない → N 画面）
    @Observable
    final class FakeCameraSource: CameraSource {
        enum Shot: Equatable {
            case cover(String)
            case blank
            case noCover
        }

        static let defaultScenario: [Shot] = [
            .cover("PAPER COMETS"), .cover("THE QUIET ORCHARD"), .cover("NORTHERN LANTERNS"), .blank, .noCover,
        ]

        let scenario: [Shot]
        private(set) var index = 0
        private(set) var liveQuad: CoverQuad?
        let authorization: CameraAuthorization = .authorized
        /// ファインダーに映す、次に撮る画像
        private(set) var preview: UIImage

        init(scenario: [Shot] = FakeCameraSource.defaultScenario) {
            self.scenario = scenario.isEmpty ? Self.defaultScenario : scenario
            self.preview = Self.render(self.scenario[0], size: CGSize(width: 384, height: 512))
        }

        /// 起動引数のシナリオ文字列を読む
        static func parse(_ text: String) -> [Shot] {
            text.split(separator: ",").map { part in
                let item = part.trimmingCharacters(in: .whitespaces)
                if item == "blank" { return .blank }
                if item == "nocover" { return .noCover }
                if item.hasPrefix("cover:") { return .cover(String(item.dropFirst("cover:".count))) }
                return .cover(item)
            }
        }

        func requestAccess() async -> Bool { true }
        func start() {}
        func stop() {}

        func capturePhoto() async throws -> Data {
            let shot = scenario[index % scenario.count]
            index += 1
            preview = Self.render(scenario[index % scenario.count], size: CGSize(width: 384, height: 512))
            let image = Self.render(shot, size: CGSize(width: 1536, height: 2048))
            guard let data = image.jpegData(compressionQuality: 0.9) else { throw CameraError.noPhotoData }
            return data
        }

        /// 合成画像を描く（scripts/generate-cover-fixtures.py の合成表紙と同じ考え方。架空の題名のみ）
        static func render(_ shot: Shot, size: CGSize) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                let cg = context.cgContext
                let w = size.width
                let h = size.height
                // 机（暗い木目調のグラデーション）
                let colors =
                    [
                        UIColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1).cgColor,
                        UIColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1).cgColor,
                    ] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)
                {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
                }
                // 細かい模様（表紙の無い画像でも四角形が出ないよう、小さな点だけ）
                var generator = SeededGenerator(seed: 7)
                for _ in 0..<400 {
                    let x = CGFloat.random(in: 0..<w, using: &generator)
                    let y = CGFloat.random(in: 0..<h, using: &generator)
                    let r = CGFloat.random(in: 1...(w / 200), using: &generator)
                    cg.setFillColor(
                        UIColor(white: CGFloat.random(in: 0.1...0.5, using: &generator), alpha: 0.5).cgColor)
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
                if shot == .noCover { return }

                // 少し傾いた表紙（縦横比 1:1.45）
                cg.saveGState()
                cg.translateBy(x: w * 0.5, y: h * 0.5)
                cg.rotate(by: -0.06)
                let coverW = w * 0.62
                let coverH = coverW * 1.45
                let cover = CGRect(x: -coverW / 2, y: -coverH / 2, width: coverW, height: coverH)
                cg.setFillColor(UIColor(red: 0.93, green: 0.91, blue: 0.86, alpha: 1).cgColor)
                cg.fill(cover)
                // 下の方の色の帯
                cg.setFillColor(UIColor(red: 0.36, green: 0.54, blue: 0.45, alpha: 1).cgColor)
                cg.fill(CGRect(x: cover.minX, y: cover.maxY - coverH * 0.22, width: coverW, height: coverH * 0.14))
                if case .cover(let title) = shot {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = .center
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: coverW * 0.11, weight: .heavy),
                        .foregroundColor: UIColor(white: 0.08, alpha: 1),
                        .paragraphStyle: paragraph,
                    ]
                    let text = NSAttributedString(string: title, attributes: attributes)
                    text.draw(
                        in: CGRect(
                            x: cover.minX + coverW * 0.08, y: cover.minY + coverH * 0.14,
                            width: coverW * 0.84, height: coverH * 0.5))
                }
                cg.restoreGState()
            }
        }
    }

    /// 再現できる乱数（合成画像の模様を毎回同じにする）
    nonisolated struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
#endif
