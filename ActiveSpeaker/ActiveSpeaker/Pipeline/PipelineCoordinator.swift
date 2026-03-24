import AVFoundation
import CoreVideo
import os

/// Central orchestrator: receives audio/video buffers, routes them through
/// processors, fuses results, and publishes state to the UI.
///
/// Thread safety model:
/// - `audioProcessors` / `mouthMovementProcessor` / `faceDetectionProvider` /
///   `faceEmbeddingProcessor` / `transcriptionProvider` are set once via
///   `configure()` before any processing starts, then only read.
/// - `_lockedAudioProb` / `_lockedMouthVar` are written from processing queues and read
///   cross-queue, protected by `os_unfair_lock`.
/// - Published properties are updated exclusively on the main thread.
/// - Transcription runs on its own serial queue to avoid blocking the audio path.
final class PipelineCoordinator: ObservableObject {

    // MARK: - Published state (read/written on main thread only)

    @Published private(set) var speakerState: SpeakerState = .silent
    @Published private(set) var audioProb: Float = 0.0
    @Published private(set) var mouthVariance: Float = 0.0
    @Published private(set) var transcriptText: String = ""
    @Published private(set) var identifiedFaces: [IdentifiedFace] = []

    // MARK: - Food logging trigger

    @Published private(set) var foodLoggingTriggered: Bool = false
    private var foodLoggingCooldown: Bool = false

    // MARK: - Processors (set once before processing starts)

    private var audioProcessors: [AudioProcessor] = []
    private var mouthMovementProcessor: MouthMovementProcessor?
    private var transcriptionProvider: TranscriptionProvider?
    private var faceDetectionProvider: FaceDetectionProvider?
    private var faceEmbeddingProcessor: FaceEmbeddingProcessor?
    private let fusionEngine = FusionEngine()

    // MARK: - Transcription queue (separate from audio to avoid blocking VAD)

    private let transcriptionQueue = DispatchQueue(
        label: "com.activespeaker.transcription",
        qos: .userInitiated
    )

    // MARK: - Shared mutable state (cross-queue)

    private var _lock = os_unfair_lock()
    private var _lockedAudioProb: Float = 0.0
    private var _lockedMouthVar: Float = 0.0

    // MARK: - Configuration

    /// Must be called on the main thread before starting capture.
    func configure(
        audioProcessors: [AudioProcessor],
        mouthMovementProcessor: MouthMovementProcessor? = nil,
        transcriptionProvider: TranscriptionProvider? = nil,
        faceDetectionProvider: FaceDetectionProvider? = nil,
        faceEmbeddingProcessor: FaceEmbeddingProcessor? = nil
    ) {
        self.audioProcessors = audioProcessors
        self.mouthMovementProcessor = mouthMovementProcessor
        self.transcriptionProvider = transcriptionProvider
        self.faceDetectionProvider = faceDetectionProvider
        self.faceEmbeddingProcessor = faceEmbeddingProcessor

        transcriptionProvider?.onTranscriptUpdate = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.transcriptText = text
                self.checkFoodLoggingTrigger(text)
            }
        }
    }

    /// Start the transcription stream. Call after configure and before capture starts.
    func startTranscription() {
        transcriptionQueue.async { [weak self] in
            self?.transcriptionProvider?.start()
        }
    }

    /// Stop the transcription stream. Call when capture stops.
    func stopTranscription() {
        transcriptionQueue.async { [weak self] in
            self?.transcriptionProvider?.stop()
        }
    }

    // MARK: - Buffer ingestion (called from dedicated processing queues)

    func processAudio(_ buffer: AVAudioPCMBuffer) {
        var prob: Float = 0.0
        for processor in audioProcessors {
            prob = processor.process(buffer: buffer)
        }

        // Feed audio to transcription on a separate queue to avoid blocking VAD.
        if let provider = transcriptionProvider {
            let samples = Self.extractSamples(from: buffer)
            transcriptionQueue.async {
                provider.feedAudio(samples: samples, sampleRate: 16000)
            }
        }

        os_unfair_lock_lock(&_lock)
        _lockedAudioProb = prob
        let mv = _lockedMouthVar
        os_unfair_lock_unlock(&_lock)

        let state = fusionEngine.fuse(audioProb: prob, mouthVariance: mv)

        DispatchQueue.main.async { [weak self] in
            self?.audioProb = prob
            self?.speakerState = state
        }
    }

    func processVideo(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        // 1. Shared face detection (one pass for all consumers)
        let faces = faceDetectionProvider?.detectFaces(
            in: pixelBuffer, orientation: orientation
        ) ?? []

        // 2. Mouth movement from detected faces
        let mouthVar = mouthMovementProcessor?.process(faces: faces) ?? 0.0

        // 3. Face identity matching (throttled internally by FaceEmbeddingProcessor)
        let identified = faceEmbeddingProcessor?.identify(
            faces: faces, in: pixelBuffer
        ) ?? faces.map {
            IdentifiedFace(name: "Unknown", boundingBox: $0.boundingBox, confidence: 0)
        }

        // 4. Cross-queue state update
        os_unfair_lock_lock(&_lock)
        _lockedMouthVar = mouthVar
        let ap = _lockedAudioProb
        os_unfair_lock_unlock(&_lock)

        let state = fusionEngine.fuse(audioProb: ap, mouthVariance: mouthVar)

        DispatchQueue.main.async { [weak self] in
            self?.mouthVariance = mouthVar
            self?.speakerState = state
            self?.identifiedFaces = identified
        }
    }

    // MARK: - Food Logging Trigger

    private func checkFoodLoggingTrigger(_ text: String) {
        guard !foodLoggingCooldown else { return }
        let lower = text.lowercased()
        if lower.contains("log food") || lower.contains("lock food") || lower.contains("log my food") {
            foodLoggingTriggered = true
            foodLoggingCooldown = true
            NSLog("[Pipeline] food logging triggered by voice: \(text)")

            // Reset trigger after a brief delay so it can be observed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.foodLoggingTriggered = false
            }

            // Cooldown: don't re-trigger for 35 seconds (recording window + buffer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.foodLoggingCooldown = false
            }
        }
    }

    /// Manually trigger food logging (e.g., from a button).
    func triggerFoodLogging() {
        guard !foodLoggingCooldown else { return }
        foodLoggingTriggered = true
        foodLoggingCooldown = true
        NSLog("[Pipeline] food logging triggered manually")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.foodLoggingTriggered = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.foodLoggingCooldown = false
        }
    }

    // MARK: - Helpers

    /// Extract Float samples from an AVAudioPCMBuffer (assumes Float32 format).
    private static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }
}
