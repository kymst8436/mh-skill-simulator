import SwiftUI
import AVFoundation
import Vision
import MHSimulatorCore

/// 護石スキャン(画面設計4.13)。ガイド枠にゲームの装備詳細(護石)を収めると
/// スキル構成を読み取り、護石入力へプリセットする(F-10=仕様3.6)
struct CharmScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CharmScanViewModel

    init(dependencies: AppDependencies, onScanned: @escaping ([CharmRules.GroupEntry], Int?) -> Void) {
        _viewModel = State(initialValue: CharmScanViewModel(
            dependencies: dependencies, onScanned: onScanned))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                switch viewModel.permission {
                case .granted:
                    scanner(size: geometry.size)
                case .denied:
                    permissionGuidance
                case .undetermined:
                    Color.clear  // OS権限ダイアログ表示中
                }
                cancelButton
            }
        }
        .onAppear { viewModel.requestPermission() }
        .statusBarHidden()
    }

    /// ガイド枠: 中央・幅約80%・縦横比3:4(画面設計4.13 構成要素3)
    static func guideRect(in size: CGSize) -> CGRect {
        let width = size.width * 0.8
        let height = min(width * 4 / 3, size.height * 0.6)
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height)
    }

    private func scanner(size: CGSize) -> some View {
        let guide = Self.guideRect(in: size)
        return ZStack {
            CharmScanCameraView(
                parser: viewModel.parser,
                guideRect: guide
            ) { reading in
                viewModel.handle(reading: reading)
            }
            .ignoresSafeArea()

            // 枠外の暗転オーバーレイ(ガイド枠を切り抜く)
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .reverseMask {
                    RoundedRectangle(cornerRadius: 12)
                        .frame(width: guide.width, height: guide.height)
                        .position(x: guide.midX, y: guide.midY)
                }
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: guide.width, height: guide.height)
                .position(x: guide.midX, y: guide.midY)

            Text("ゲームの装備詳細(護石)を枠内に収めてください")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .position(x: size.width / 2, y: min(guide.maxY + 36, size.height - 40))
        }
    }

    private var permissionGuidance: some View {
        VStack(spacing: 0) {
            MHEmptyState(
                systemImage: "camera",
                title: String(localized: "カメラを使用できません"),
                message: String(localized: "設定アプリでカメラへのアクセスを許可してください"),
                actionTitle: String(localized: "設定を開く")
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .colorScheme(.dark)
    }

    private var cancelButton: some View {
        VStack {
            HStack {
                Button("キャンセル") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.black.opacity(0.4), in: Capsule())
                Spacer()
            }
            Spacer()
        }
        .padding(16)
    }
}

/// カメラプレビュー+フレームOCR(AVFoundation+Vision)。
/// ガイド枠内のみを認識対象にし、解釈結果(Reading?)をMainActorへ返す
private struct CharmScanCameraView: UIViewRepresentable {
    let parser: CharmScanParser
    let guideRect: CGRect
    let onReading: (CharmScanParser.Reading?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parser: parser, onReading: onReading)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start(attachingTo: view.previewLayer)
        context.coordinator.updateGeometry(guideRect: guideRect, viewSize: nil)
        view.onLayout = { [weak coordinator = context.coordinator] layer in
            coordinator?.updateGeometry(guideRect: nil, viewSize: layer.bounds.size)
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.updateGeometry(guideRect: guideRect, viewSize: view.bounds.size)
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onLayout: ((AVCaptureVideoPreviewLayer) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(previewLayer)
        }
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let parser: CharmScanParser
        private let onReading: (CharmScanParser.Reading?) -> Void
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "charm-scan.session")
        private let videoQueue = DispatchQueue(label: "charm-scan.vision")
        /// ガイド枠とプレビューサイズ(ビュー座標)。フレーム処理時に画像座標へ変換する
        private let geometryLock = NSLock()
        private var guideRect: CGRect?
        private var viewSize: CGSize?
        private var isProcessing = false

        /// ガイド枠の許容マージン(枠ぴったりに収めた際のはみ出しを吸収する。各辺25%拡張)
        private static let guideMargin: CGFloat = 0.25

        init(parser: CharmScanParser, onReading: @escaping (CharmScanParser.Reading?) -> Void) {
            self.parser = parser
            self.onReading = onReading
        }

        func start(attachingTo previewLayer: AVCaptureVideoPreviewLayer) {
            previewLayer.session = session
            sessionQueue.async { [self] in
                configureSession()
                session.startRunning()
            }
        }

        func stop() {
            sessionQueue.async { [self] in
                session.stopRunning()
            }
        }

        private func configureSession() {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            // ライブフレームの解像度が読み取り精度を左右する(仕様3.6: 1080p以上)
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            // 縦向きに揃える(プレビューと出力バッファの座標系を一致させる)
            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        /// ガイド枠・プレビューサイズの更新(nilの引数は保持値を維持)
        func updateGeometry(guideRect: CGRect?, viewSize: CGSize?) {
            geometryLock.lock()
            if let guideRect { self.guideRect = guideRect }
            if let viewSize, viewSize.width > 0 { self.viewSize = viewSize }
            geometryLock.unlock()
        }

        /// ガイド枠(ビュー座標)を正規化画像座標(原点左上)へ変換し、マージン分拡張する。
        /// プレビューはアスペクトフィル表示のため、はみ出し分のオフセットを補正する
        static func normalizedGuideRect(
            guide: CGRect, viewSize: CGSize, imageSize: CGSize, margin: CGFloat
        ) -> CGRect? {
            guard viewSize.width > 0, viewSize.height > 0,
                  imageSize.width > 0, imageSize.height > 0 else { return nil }
            let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
            let displayed = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let offset = CGPoint(
                x: (displayed.width - viewSize.width) / 2,
                y: (displayed.height - viewSize.height) / 2)
            let normalized = CGRect(
                x: (guide.minX + offset.x) / displayed.width,
                y: (guide.minY + offset.y) / displayed.height,
                width: guide.width / displayed.width,
                height: guide.height / displayed.height)
            return normalized
                .insetBy(dx: -normalized.width * margin, dy: -normalized.height * margin)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            geometryLock.lock()
            let guide = guideRect
            let view = viewSize
            geometryLock.unlock()
            guard !isProcessing, let guide, let view,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer))
            // 全フレームを認識し、ガイド枠(マージン付き)内のテキストだけ採用する。
            // ROI指定は使わない(座標変換ズレで枠と認識領域が食い違う事故を避ける。F10-4フィードバック)
            guard let filterRect = Self.normalizedGuideRect(
                guide: guide, viewSize: view, imageSize: imageSize, margin: Self.guideMargin)
            else { return }
            isProcessing = true

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
            try? handler.perform([request])

            let observations = (request.results ?? []).compactMap { observation -> CharmScanParser.ObservedText? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.3 else { return nil }
                // yは上→下に増える読み取り順へ変換(Visionは原点左下)
                let center = CGPoint(
                    x: observation.boundingBox.midX,
                    y: 1 - observation.boundingBox.midY)
                guard filterRect.contains(center) else { return nil }
                return CharmScanParser.ObservedText(text: candidate.string, x: center.x, y: center.y)
            }
            let reading = parser.parse(observations)
            DispatchQueue.main.async { [self] in
                onReading(reading)
            }
            isProcessing = false
        }
    }
}
