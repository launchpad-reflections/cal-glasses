import AVFoundation
import CoreMedia
import MWDATCamera
import MWDATCore
import SwiftUI

/// Manages video/audio streaming from Meta glasses via MWDAT SDK.
/// Feeds frames and audio into the shared PipelineCoordinator for
/// face detection, transcription, and speaker state analysis.
@MainActor
final class GlassesStreamManager: ObservableObject {

    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var hasReceivedFirstFrame: Bool = false
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var streamStatus: String = "Stopped"
    @Published private(set) var hasActiveDevice: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private let wearables: WearablesInterface
    private var streamSession: StreamSession
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private let deviceSelector: AutoDeviceSelector
    private var deviceMonitorTask: Task<Void, Never>?
    private let audioCapture = GlassesAudioCapture()
    private let speaker = GlassesSpeaker()

    /// Pipeline coordinator for running face detection + transcription on glasses stream.
    weak var coordinator: PipelineCoordinator?

    /// Video processing queue (matches CaptureManager pattern).
    private let videoProcessingQueue = DispatchQueue(
        label: "com.activespeaker.glasses.video",
        qos: .userInteractive
    )

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 24
        )
        streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

        NSLog("[GlassesStream] init: session created (high res, raw), setting up listeners")
        setupListeners()
        monitorDevices()
        updateStatusFromState(streamSession.state)
    }

    func startStreaming() async {
        guard !isStreaming else { return }

        // Request camera permission from glasses
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

        // Set up HFP audio session BEFORE starting stream
        do {
            try audioCapture.setupAudioSession()
        } catch {
            NSLog("[GlassesStream] HFP audio session setup failed: \(error)")
        }

        // Wait for HFP to stabilize (Meta docs requirement)
        try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)

        await streamSession.start()

        // Start audio capture and feed to pipeline
        if !audioCapture.isRunning {
            do {
                try audioCapture.start(coordinator: coordinator)
            } catch {
                NSLog("[GlassesStream] Failed to start mic: \(error)")
            }
        }

        coordinator?.startTranscription()

        // Speak the startup prompt through the glasses
        let promptText = GlassesPrompt.defaultPrompt
        speaker.speak(promptText)
        NSLog("[GlassesStream] speaking prompt (\(promptText.count) chars)")
    }

    func stopStreaming() async {
        speaker.stop()
        audioCapture.stop()
        coordinator?.stopTranscription()
        await streamSession.stop()
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }

    // MARK: - Private

    private func setupListeners() {
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusFromState(state)
            }
        }

        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            // Get the CMSampleBuffer directly — no UIImage conversion needed for pipeline.
            // This is much faster and gives Vision the native pixel buffer.
            let sampleBuffer = videoFrame.sampleBuffer

            Task { @MainActor [weak self] in
                guard let self else { return }

                // Update UI with UIImage (only for display)
                if let image = videoFrame.makeUIImage() {
                    self.currentFrame = image
                    if !self.hasReceivedFirstFrame {
                        NSLog("[GlassesStream] first frame received! size=\(image.size)")
                        self.hasReceivedFirstFrame = true
                    }
                }

                // Feed pixel buffer directly to pipeline on background queue
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
