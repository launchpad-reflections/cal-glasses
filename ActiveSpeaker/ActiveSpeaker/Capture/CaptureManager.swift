import AVFoundation
import os

/// Manages video capture (AVCaptureSession) and audio capture (AVAudioEngine).
/// Routes buffers to PipelineCoordinator for processing.
final class CaptureManager: NSObject, ObservableObject {

    let captureSession = AVCaptureSession()

    private let videoProcessingQueue = DispatchQueue(
        label: "com.activespeaker.video",
        qos: .userInteractive
    )
    private let audioProcessingQueue = DispatchQueue(
        label: "com.activespeaker.audio",
        qos: .userInteractive
    )

    private var audioEngine: AVAudioEngine?
    private var performanceActivity: NSObjectProtocol?
    weak var coordinator: PipelineCoordinator?

    // MARK: - Public

    private let sessionQueue = DispatchQueue(label: "com.activespeaker.session")

    func start() {
        requestPermissions { [weak self] granted in
            guard granted, let self else { return }
            self.configureAudioSession()
            self.configureVideoCapture()
            self.configureAudioCapture()
            self.beginPerformanceActivity()
            self.sessionQueue.async {
                self.captureSession.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            captureSession.stopRunning()
        }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        if let activity = performanceActivity {
            ProcessInfo.processInfo.endActivity(activity)
            performanceActivity = nil
        }
    }

    // MARK: - Permissions

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        var cameraGranted = false
        var micGranted = false
        let group = DispatchGroup()

        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraGranted = granted
            group.leave()
        }

        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micGranted = granted
            group.leave()
        }

        group.notify(queue: .main) {
            completion(cameraGranted && micGranted)
        }
    }

    // MARK: - Audio Session (low-latency configuration)

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setPreferredSampleRate(16000)
            try session.setActive(true)
        } catch {
            print("[CaptureManager] Audio session error: \(error)")
        }
    }

    // MARK: - Video Capture

    private func configureVideoCapture() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Front camera
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            print("[CaptureManager] No front camera available")
            captureSession.commitConfiguration()
            return
        }

        // Lock frame rate
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
            camera.unlockForConfiguration()
        } catch {
            print("[CaptureManager] Failed to lock camera config: \(error)")
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        // Output — YCbCr to avoid ISP color conversion
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Mirror front camera
        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = true
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Audio Capture (AVAudioEngine for low latency)

    private func configureAudioCapture() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Use the hardware format for the tap — passing a different sample rate crashes
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32 — matches Silero VAD requirements
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            print("[CaptureManager] Failed to create target audio format")
            return
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            print("[CaptureManager] Failed to create audio converter")
            return
        }

        // Install tap at hardware rate, then convert to 16kHz mono
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) {
            [weak self] buffer, _ in
            // Calculate the output frame count based on the rate ratio
            let ratio = 16000.0 / hwFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, outputBuffer.frameLength > 0 {
                self?.coordinator?.processAudio(outputBuffer)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
        } catch {
            print("[CaptureManager] Audio engine error: \(error)")
        }
    }

    // MARK: - Performance

    private func beginPerformanceActivity() {
        performanceActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Real-time active speaker detection"
        )
    }
}

// MARK: - Video Sample Buffer Delegate

extension CaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        coordinator?.processVideo(
            pixelBuffer: pixelBuffer,
            orientation: .leftMirrored
        )
    }
}
