import SwiftUI

struct ContentView: View {

    @StateObject private var coordinator = PipelineCoordinator()
    @StateObject private var captureManager = CaptureManager()

    var body: some View {
        ZStack {
            CameraPreviewView(session: captureManager.captureSession)
                .ignoresSafeArea()

            StatusOverlayView(
                state: coordinator.speakerState,
                audioProb: coordinator.audioProb,
                mouthVariance: coordinator.mouthVariance
            )

            TranscriptOverlayView(text: coordinator.transcriptText)
        }
        .onAppear {
            coordinator.configure(
                audioProcessors: [SileroVADProcessor()],
                videoProcessors: [MouthMovementProcessor()],
                transcriptionProvider: MoonshineTranscriber()
            )
            coordinator.startTranscription()
            captureManager.coordinator = coordinator
            captureManager.start()
        }
        .onDisappear {
            coordinator.stopTranscription()
            captureManager.stop()
        }
    }
}
