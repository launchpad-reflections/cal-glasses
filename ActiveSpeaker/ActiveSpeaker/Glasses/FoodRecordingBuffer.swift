import UIKit

/// Captures frames (at ~1fps) and transcript text during a 30-second food logging window.
final class FoodRecordingBuffer {

    struct FoodRecording {
        let frames: [UIImage]
        let transcript: String
    }

    private var frames: [(image: UIImage, time: TimeInterval)] = []
    private var transcriptSegments: [String] = []
    private var startTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private(set) var isRecording = false

    /// Minimum interval between captured frames (1 second).
    private let frameInterval: TimeInterval = 1.0

    func startRecording() {
        frames.removeAll()
        transcriptSegments.removeAll()
        startTime = CACurrentMediaTime()
        lastFrameTime = 0
        isRecording = true
        NSLog("[FoodBuffer] recording started")
    }

    func stopRecording() -> FoodRecording {
        isRecording = false
        let result = FoodRecording(
            frames: frames.map(\.image),
            transcript: transcriptSegments.joined(separator: " ")
        )
        NSLog("[FoodBuffer] recording stopped: \(result.frames.count) frames, transcript: \(result.transcript.prefix(100))...")
        return result
    }

    /// Add a frame from the glasses stream. Throttled to ~1fps.
    func addFrame(_ image: UIImage) {
        guard isRecording else { return }
        let now = CACurrentMediaTime()
        let elapsed = now - startTime

        guard elapsed - lastFrameTime >= frameInterval else { return }
        lastFrameTime = elapsed
        frames.append((image: image, time: elapsed))
    }

    /// Add a transcript segment.
    func addTranscript(_ text: String) {
        guard isRecording, !text.isEmpty else { return }
        // Replace last segment if it's a continuation (Moonshine updates in-place)
        if !transcriptSegments.isEmpty {
            transcriptSegments[transcriptSegments.count - 1] = text
        } else {
            transcriptSegments.append(text)
        }
    }

    /// Called when a transcript line is finalized.
    func finalizeTranscriptLine() {
        guard isRecording else { return }
        transcriptSegments.append("")
    }
}
