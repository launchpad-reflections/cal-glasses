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
        }
        .onAppear {
            coordinator.configure(
                audioProcessors: [SileroVADProcessor()],
                videoProcessors: [MouthMovementProcessor()]
            )
            captureManager.coordinator = coordinator
            captureManager.start()
        }
        .onDisappear {
            captureManager.stop()
        }
    }
}
