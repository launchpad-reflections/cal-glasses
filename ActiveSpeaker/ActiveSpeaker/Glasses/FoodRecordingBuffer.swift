import UIKit

/// Captures frames (at ~1fps) and transcript text during a food logging window.
final class FoodRecordingBuffer {

    struct FoodRecording {
        let frames: [UIImage]
        let transcript: String
    }

    private var frames: [(image: UIImage, time: TimeInterval)] = []
    private var allTranscriptText: String = ""
    private var lastTranscriptUpdate: String = ""
    private var startTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private(set) var isRecording = false

    /// Minimum interval between captured frames (1 second).
    private let frameInterval: TimeInterval = 1.0

    func startRecording() {
        frames.removeAll()
        allTranscriptText = ""
        lastTranscriptUpdate = ""
        startTime = CACurrentMediaTime()
        lastFrameTime = 0
        isRecording = true
        NSLog("[FoodBuffer] recording started")
    }

    func stopRecording() -> FoodRecording {
        isRecording = false
        // Append the last in-progress transcript update
        if !lastTranscriptUpdate.isEmpty {
            allTranscriptText += lastTranscriptUpdate
        }
        let finalTranscript = allTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = FoodRecording(
            frames: frames.map(\.image),
            transcript: finalTranscript
        )
        NSLog("[FoodBuffer] recording stopped: \(result.frames.count) frames, transcript: '\(result.transcript.prefix(200))'")
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

    /// Add a transcript update. Moonshine sends the current line repeatedly
    /// (updating in-place), so we track the latest version and append when new lines start.
    func addTranscript(_ text: String) {
        guard isRecording, !text.isEmpty else { return }

        // If this is a completely new text (not an update of the previous),
        // save the previous and start fresh
        if !lastTranscriptUpdate.isEmpty && !text.hasPrefix(lastTranscriptUpdate.prefix(10)) {
            allTranscriptText += lastTranscriptUpdate + " "
        }
        lastTranscriptUpdate = text
        NSLog("[FoodBuffer] transcript update: '\(text.prefix(80))'")
    }
}
