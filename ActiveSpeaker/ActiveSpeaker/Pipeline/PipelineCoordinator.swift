import AVFoundation
import CoreVideo
import os

/// Central orchestrator: receives audio/video buffers, routes them through
/// processors, fuses results, and publishes state to the UI.
///
/// Thread safety model:
/// - `audioProcessors` / `videoProcessors` are set once via `configure()` before
///   any processing starts, then only read. No synchronization needed.
/// - `_audioProb` / `_mouthVar` are written from processing queues and read
///   cross-queue, protected by `os_unfair_lock`.
/// - Published properties are updated exclusively on the main thread.
final class PipelineCoordinator: ObservableObject {

    // MARK: - Published state (read/written on main thread only)

    @Published private(set) var speakerState: SpeakerState = .silent
    @Published private(set) var audioProb: Float = 0.0
    @Published private(set) var mouthVariance: Float = 0.0

    // MARK: - Processors (set once before processing starts)

    private var audioProcessors: [AudioProcessor] = []
    private var videoProcessors: [VideoProcessor] = []
    private let fusionEngine = FusionEngine()

    // MARK: - Shared mutable state (cross-queue)

    private var _lock = os_unfair_lock()
    private var _audioProb: Float = 0.0
    private var _mouthVar: Float = 0.0

    // MARK: - Configuration

    /// Must be called on the main thread before starting capture.
    func configure(audioProcessors: [AudioProcessor], videoProcessors: [VideoProcessor]) {
        self.audioProcessors = audioProcessors
        self.videoProcessors = videoProcessors
    }

    // MARK: - Buffer ingestion (called from dedicated processing queues)

    func processAudio(_ buffer: AVAudioPCMBuffer) {
        var prob: Float = 0.0
        for processor in audioProcessors {
            prob = processor.process(buffer: buffer)
        }

        os_unfair_lock_lock(&_lock)
        _audioProb = prob
        let mv = _mouthVar
        os_unfair_lock_unlock(&_lock)

        let state = fusionEngine.fuse(audioProb: prob, mouthVariance: mv)

        DispatchQueue.main.async { [weak self] in
            self?.audioProb = prob
            self?.speakerState = state
        }
    }

    func processVideo(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        var mouthVar: Float = 0.0
        for processor in videoProcessors {
            mouthVar = processor.process(pixelBuffer: pixelBuffer, orientation: orientation)
        }

        os_unfair_lock_lock(&_lock)
        _mouthVar = mouthVar
        let ap = _audioProb
        os_unfair_lock_unlock(&_lock)

        let state = fusionEngine.fuse(audioProb: ap, mouthVariance: mouthVar)

        DispatchQueue.main.async { [weak self] in
            self?.mouthVariance = mouthVar
            self?.speakerState = state
        }
    }
}
