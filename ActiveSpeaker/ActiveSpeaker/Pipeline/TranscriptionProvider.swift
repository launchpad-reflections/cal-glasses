import Foundation

/// Protocol for speech-to-text providers in the pipeline.
///
/// Unlike `AudioProcessor` (which returns a scalar per buffer), transcription
/// providers consume audio samples continuously and produce text via a callback.
/// Implementations are called on a dedicated serial queue — they need not be thread-safe.
protocol TranscriptionProvider: AnyObject {
    var name: String { get }

    /// Called when new transcript text is available. Set by PipelineCoordinator.
    var onTranscriptUpdate: ((String) -> Void)? { get set }

    /// Feed raw PCM audio samples for transcription.
    func feedAudio(samples: [Float], sampleRate: Int32)

    /// Begin processing. Called when capture starts.
    func start()

    /// Stop processing. Called when capture stops.
    func stop()

    /// Reset internal state (e.g., between utterances or on restart).
    func reset()
}
