import AVFoundation
import MWDATCamera
import MWDATCore
import SwiftUI

/// Manages video/audio streaming from Meta glasses via MWDAT SDK.
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

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )
        streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

        NSLog("[GlassesStream] init: session created, setting up listeners")
        setupListeners()
        monitorDevices()
        updateStatusFromState(streamSession.state)
    }

    func startStreaming() async {
        guard !isStreaming else {
            NSLog("[GlassesStream] startStreaming called but already streaming, ignoring")
            return
        }
        NSLog("[GlassesStream] startStreaming called, hasActiveDevice=\(hasActiveDevice)")

        // Request camera permission from glasses
        do {
            NSLog("[GlassesStream] checking camera permission...")
            let status = try await wearables.checkPermissionStatus(.camera)
            NSLog("[GlassesStream] permission status: \(status)")
            if status != .granted {
                NSLog("[GlassesStream] requesting camera permission...")
                let result = try await wearables.requestPermission(.camera)
                NSLog("[GlassesStream] permission result: \(result)")
                guard result == .granted else {
                    showStreamError("Camera permission denied.")
                    return
                }
            }
        } catch {
            NSLog("[GlassesStream] permission error: \(error)")
            showStreamError("Permission error: \(error)")
            return
        }

        // Set up HFP audio session BEFORE starting stream
        NSLog("[GlassesStream] setting up HFP audio session...")
        do {
            try audioCapture.setupAudioSession()
            NSLog("[GlassesStream] HFP audio session configured")
        } catch {
            NSLog("[GlassesStream] HFP audio session setup failed: \(error)")
        }

        // Wait for HFP to stabilize (Meta docs requirement)
        NSLog("[GlassesStream] waiting 2s for HFP stabilization...")
        try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)

        // Start streaming
        NSLog("[GlassesStream] calling streamSession.start()...")
        await streamSession.start()
        NSLog("[GlassesStream] streamSession.start() returned, state=\(streamSession.state)")
    }

    func stopStreaming() async {
        audioCapture.stop()
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
                NSLog("[GlassesStream] state changed: \(state)")
                self.updateStatusFromState(state)
            }
        }

        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let image = videoFrame.makeUIImage() {
                    self.currentFrame = image
                    if !self.hasReceivedFirstFrame {
                        NSLog("[GlassesStream] first frame received! size=\(image.size)")
                        self.hasReceivedFirstFrame = true
                    }
                }
            }
        }

        errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                NSLog("[GlassesStream] stream error: \(error)")
                self.showStreamError(self.formatError(error))
            }
        }
    }

    private func monitorDevices() {
        deviceMonitorTask = Task { @MainActor in
            for await device in deviceSelector.activeDeviceStream() {
                let hasDevice = device != nil
                NSLog("[GlassesStream] active device changed: \(device ?? "nil"), hasDevice=\(hasDevice)")
                self.hasActiveDevice = hasDevice
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
