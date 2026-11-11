import AVFoundation
import SwiftUI
import UIKit
import os

/// カメラの使用許可の状態（O 画面の出し分けに使う）
enum CameraAuthorization: Sendable, Equatable {
    case authorized
    case notDetermined
    case denied
}

enum CameraError: Error {
    /// カメラが無い・使えない（入力・出力を構成できなかった）
    case unavailable
    /// 撮影した写真のデータを取り出せなかった
    case noPhotoData
}

/// 撮影に使うカメラ。実機は `CameraController`（AVFoundation）、シミュレータ・UIテストは `FakeCameraSource`
@MainActor
protocol CameraSource: AnyObject {
    var authorization: CameraAuthorization { get }
    /// ファインダーに映っている表紙の四隅（ライブの検出。見つからなければ nil）
    var liveQuad: CoverQuad? { get }
    func requestAccess() async -> Bool
    func start()
    func stop()
    /// 1枚撮影して、画像データ（HEIC・JPEG）を返す。返った時点で次の撮影ができる
    func capturePhoto() async throws -> Data
}

/// 実機のカメラ（requirements F1-1・F1-3）。セッションの操作は専用のキューで行う
@Observable
final class CameraController: CameraSource {
    private(set) var liveQuad: CoverQuad?
    private(set) var authorization: CameraAuthorization = CameraController.currentAuthorization()

    @ObservationIgnored let box = CaptureSessionBox()

    init() {
        box.onQuad = { [weak self] quad in
            Task { @MainActor in self?.liveQuad = quad }
        }
    }

    static func currentAuthorization() -> CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorization = Self.currentAuthorization()
        return granted
    }

    func start() {
        guard authorization == .authorized else { return }
        box.start()
    }

    func stop() {
        box.stop()
        liveQuad = nil
    }

    func capturePhoto() async throws -> Data {
        try await box.capture()
    }
}

/// AVCaptureSession と出力をまとめ、すべて専用のキュー（`queue`）の上で触る。
/// AVFoundation の型は Sendable でないため、キューで直列化したうえで `@unchecked Sendable` とする
nonisolated final class CaptureSessionBox: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate
{
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.ryutaro3215.bookshelf.camera.session")
    private let videoQueue = DispatchQueue(label: "com.ryutaro3215.bookshelf.camera.video")
    private let detector = CoverDetector()
    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Camera")
    /// ライブの検出の間隔（秒）。毎コマは重いので間引く
    private static let analysisInterval: TimeInterval = 0.25

    // queue の上だけで触る
    private var isConfigured = false
    private var configurationFailed = false
    private var pending: [Int64: PhotoCaptureDelegate] = [:]
    // videoQueue の上だけで触る
    private var lastAnalysis = Date.distantPast

    /// ライブの検出結果を受け取る（videoQueue から呼ばれる）
    var onQuad: (@Sendable (CoverQuad?) -> Void)?

    func start() {
        queue.async { [self] in
            configureIfNeeded()
            guard !configurationFailed, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async { [self] in
                guard isConfigured, !configurationFailed, session.isRunning else {
                    continuation.resume(throwing: CameraError.unavailable)
                    return
                }
                let settings = AVCapturePhotoSettings()
                // 撮影から次の撮影可能までを短くする（plan T5: 1秒以内）。表紙は静止物なので速度を優先する
                settings.photoQualityPrioritization = .speed
                let id = settings.uniqueID
                let delegate = PhotoCaptureDelegate { [weak self] result in
                    if let box = self {
                        box.queue.async { box.pending[id] = nil }
                    }
                    continuation.resume(with: result)
                }
                pending[id] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            Self.logger.error("背面カメラが見つからない")
            configurationFailed = true
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput)
            else {
                Self.logger.error("カメラの入力・出力を追加できない")
                configurationFailed = true
                return
            }
            session.addInput(input)
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)

            // 縦持ちにそろえる（写真は EXIF の向き、映像のコマは回転済み → Vision には .up で渡せる）
            for connection in [photoOutput.connection(with: .video), videoOutput.connection(with: .video)] {
                if let connection, connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        } catch {
            Self.logger.error("カメラの入力を作れない: \(error.localizedDescription, privacy: .public)")
            configurationFailed = true
        }
    }

    // MARK: - ライブの検出（AVCaptureVideoDataOutputSampleBufferDelegate）

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= Self.analysisInterval,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        lastAnalysis = now
        do {
            onQuad?(try detector.detect(in: buffer))
        } catch {
            Self.logger.debug("ライブの検出に失敗: \(error.localizedDescription, privacy: .public)")
            onQuad?(nil)
        }
    }
}

/// 1枚の撮影の完了を受け取る
nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Result<Data, Error>) -> Void

    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.noPhotoData))
            return
        }
        completion(.success(data))
    }
}

/// ファインダー（AVCaptureVideoPreviewLayer）。縦横比 3:4 の枠に、写真と同じ範囲をそのまま映す
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass で指定しているので必ずこの型
            unsafeDowncast(layer, to: AVCaptureVideoPreviewLayer.self)
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
