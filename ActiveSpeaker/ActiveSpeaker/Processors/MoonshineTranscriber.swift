import Foundation
import MoonshineVoice

/// Speech-to-text processor using Moonshine v2 (small-streaming).
///
/// Wraps the MoonshineVoice `Transcriber` + `Stream` API to accept raw PCM
/// audio and emit transcript text via `onTranscriptUpdate`. Designed to be
/// driven by `PipelineCoordinator` on a dedicated serial queue.
final class MoonshineTranscriber: TranscriptionProvider {

    let name = "moonshineV2"
    var onTranscriptUpdate: ((String) -> Void)?

    private var transcriber: MoonshineVoice.Transcriber?
    private var stream: MoonshineVoice.Stream?

    init() {
        setupTranscriber()
    }

    // MARK: - TranscriptionProvider

    func feedAudio(samples: [Float], sampleRate: Int32) {
        do {
            try stream?.addAudio(samples, sampleRate: sampleRate)
        } catch {
            print("[MoonshineTranscriber] addAudio error: \(error)")
        }
    }

    func start() {
        do {
            try stream?.start()
        } catch {
            print("[MoonshineTranscriber] start error: \(error)")
        }
    }

    func stop() {
        do {
            try stream?.stop()
        } catch {
            print("[MoonshineTranscriber] stop error: \(error)")
        }
    }

    func reset() {
        stop()
        do {
            stream = try transcriber?.createStream(updateInterval: 0.5)
            attachListeners()
        } catch {
            print("[MoonshineTranscriber] reset error: \(error)")
        }
    }

    // MARK: - Private

    private func setupTranscriber() {
        guard let resourcePath = Bundle.main.resourcePath else {
            print("[MoonshineTranscriber] Could not find main bundle resource path")
            return
        }

        // Files are copied flat into the bundle root by Xcode's Copy Bundle Resources.
        let modelPath = resourcePath
        guard FileManager.default.fileExists(atPath: modelPath.appending("/encoder.ort")) else {
            print("[MoonshineTranscriber] Model files not found in bundle at: \(modelPath)")
            return
        }

        do {
            let t = try MoonshineVoice.Transcriber(modelPath: modelPath, modelArch: .smallStreaming)
            transcriber = t
            stream = try t.createStream(updateInterval: 0.5)
            attachListeners()
        } catch {
            print("[MoonshineTranscriber] Setup error: \(error)")
        }
    }

    private func attachListeners() {
        guard let stream else { return }

        stream.addListener { [weak self] event in
            guard let self else { return }
            if event is LineStarted || event is LineTextChanged {
                self.onTranscriptUpdate?(event.line.text)
            } else if event is LineCompleted {
                if !event.line.text.isEmpty {
                    self.onTranscriptUpdate?(event.line.text)
                }
            }
        }
    }
}
