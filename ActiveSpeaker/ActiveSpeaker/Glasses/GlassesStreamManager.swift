import AVFoundation
import CoreMedia
import MWDATCamera
import MWDATCore
import SwiftUI

/// Manages video/audio streaming from Meta glasses via MWDAT SDK.
/// Orchestrates the food logging flow: voice trigger → 30s recording → dedup → Gemini → results.
@MainActor
final class GlassesStreamManager: ObservableObject {

    // MARK: - Stream state

    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var hasReceivedFirstFrame: Bool = false
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var streamStatus: String = "Stopped"
    @Published private(set) var hasActiveDevice: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    // MARK: - Food logging state

    enum FoodLoggingState: Equatable {
        case idle
        case recording(secondsLeft: Int)
        case processing
        case results
    }

    @Published private(set) var foodLoggingState: FoodLoggingState = .idle
    @Published private(set) var foodResults: FoodAnalysisResult?
    @Published private(set) var transcriptDuringRecording: String = ""

    // MARK: - Dependencies

    private let wearables: WearablesInterface
    private var streamSession: StreamSession
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private let deviceSelector: AutoDeviceSelector
    private var deviceMonitorTask: Task<Void, Never>?
    private let audioCapture = GlassesAudioCapture()
    let speaker = GlassesSpeaker()

    weak var coordinator: PipelineCoordinator?

    private let videoProcessingQueue = DispatchQueue(
        label: "com.activespeaker.glasses.video",
        qos: .userInteractive
    )

    private let recordingBuffer = FoodRecordingBuffer()
    private let gemini = GeminiService(apiKey: "YOUR_GEMINI_API_KEY")
    private var recordingTimer: Timer?
    private var recordingSecondsLeft = 0

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 24
        )
        streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

        setupListeners()
        monitorDevices()
        updateStatusFromState(streamSession.state)
    }

    // MARK: - Streaming

    func startStreaming() async {
        guard !isStreaming else { return }

        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                let result = try await wearables.requestPermission(.camera)
                guard result == .granted else {
                    showStreamError("Camera permission denied.")
                    return
                }
            }
        } catch {
            showStreamError("Permission error: \(error)")
            return
        }

        do {
            try audioCapture.setupAudioSession()
        } catch {
            NSLog("[GlassesStream] HFP audio session setup failed: \(error)")
        }

        try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)

        await streamSession.start()

        if !audioCapture.isRunning {
            do {
                try audioCapture.start(coordinator: coordinator)
            } catch {
                NSLog("[GlassesStream] Failed to start mic: \(error)")
            }
        }

        coordinator?.startTranscription()
        speaker.speak("Ready. Say log food to start tracking.")
    }

    func stopStreaming() async {
        speaker.stop()
        stopRecordingTimer()
        audioCapture.stop()
        coordinator?.stopTranscription()
        await streamSession.stop()
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }

    // MARK: - Food Logging

    /// Start a 30-second food recording window.
    func startFoodLogging() {
        guard foodLoggingState == .idle else { return }

        speaker.speak("Tracking started")
        recordingBuffer.startRecording()
        recordingSecondsLeft = 30
        foodLoggingState = .recording(secondsLeft: 30)
        transcriptDuringRecording = ""
        foodResults = nil

        NSLog("[FoodLog] recording started")

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordingSecondsLeft -= 1
                self.foodLoggingState = .recording(secondsLeft: self.recordingSecondsLeft)

                if self.recordingSecondsLeft <= 0 {
                    self.finishFoodLogging()
                }
            }
        }
    }

    /// Manually trigger food logging (from button tap).
    func manualTriggerFoodLogging() {
        startFoodLogging()
    }

    private func finishFoodLogging() {
        stopRecordingTimer()
        speaker.speak("Tracking complete. Analyzing.")

        let recording = recordingBuffer.stopRecording()
        transcriptDuringRecording = recording.transcript
        foodLoggingState = .processing

        NSLog("[FoodLog] processing \(recording.frames.count) frames, transcript: \(recording.transcript.prefix(100))")

        // Deduplicate frames
        let uniqueFrames = FrameDeduplicator.deduplicate(recording.frames)

        // Send to Gemini
        Task {
            do {
                let result = try await gemini.analyzeFoodImages(
                    images: uniqueFrames,
                    transcript: recording.transcript
                )
                self.foodResults = result
                self.foodLoggingState = .results

                // Announce results
                let itemNames = result.items.map(\.name).joined(separator: ", ")
                if result.items.isEmpty {
                    self.speaker.speak("No food detected.")
                } else {
                    self.speaker.speak("Found \(result.items.count) items: \(itemNames)")
                }
            } catch {
                NSLog("[FoodLog] Gemini error: \(error)")
                self.showStreamError("Analysis failed: \(error.localizedDescription)")
                self.foodLoggingState = .idle
            }
        }
    }

    /// Reset to idle state after viewing results.
    func dismissResults() {
        foodLoggingState = .idle
        foodResults = nil
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - Listeners

    private func setupListeners() {
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusFromState(state)
            }
        }

        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            let sampleBuffer = videoFrame.sampleBuffer

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let image = videoFrame.makeUIImage() {
                    self.currentFrame = image
                    if !self.hasReceivedFirstFrame {
                        NSLog("[GlassesStream] first frame received! size=\(image.size)")
                        self.hasReceivedFirstFrame = true
                    }

                    // Feed frame to recording buffer if active
                    self.recordingBuffer.addFrame(image)
                }

                // Feed to pipeline for transcription
                if let coordinator = self.coordinator,
                   let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    self.videoProcessingQueue.async {
                        coordinator.processVideo(
                            pixelBuffer: pixelBuffer,
                            orientation: .up
                        )
                    }
                }
            }
        }

        errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.showStreamError(self.formatError(error))
            }
        }
    }

    private func monitorDevices() {
        deviceMonitorTask = Task { @MainActor in
            for await device in deviceSelector.activeDeviceStream() {
                self.hasActiveDevice = device != nil
            }
        }
    }

    private func updateStatusFromState(_ state: StreamSessionState) {
        switch state {
        case .stopped:
            currentFrame = nil
            hasReceivedFirstFrame = false
            isStreaming = false
            streamStatus = "Stopped"
        case .streaming:
            isStreaming = true
            streamStatus = "Streaming"
        case .waitingForDevice, .starting, .stopping, .paused:
            isStreaming = false
            streamStatus = "Waiting..."
        @unknown default:
            isStreaming = false
            streamStatus = "Unknown"
        }
    }

    private func showStreamError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func formatError(_ error: StreamSessionError) -> String {
        switch error {
        case .internalError:                return "An internal error occurred."
        case .deviceNotFound:               return "Glasses not found."
        case .deviceNotConnected:           return "Glasses disconnected."
        case .timeout:                      return "Timed out. Try again."
        case .videoStreamingError:          return "Video stream failed."
        case .permissionDenied:             return "Camera permission denied."
        case .hingesClosed:                 return "Open the glasses hinges."
        case .thermalCritical:              return "Device overheating."
        @unknown default:                   return "An unknown error occurred."
        }
    }
}
