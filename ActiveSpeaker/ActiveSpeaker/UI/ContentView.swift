import SwiftUI

struct ContentView: View {

    @ObservedObject var coordinator: PipelineCoordinator
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var gallery: FaceGallery

    var body: some View {
        ZStack {
            CameraPreviewView(
                session: captureManager.captureSession,
                faces: coordinator.identifiedFaces,
                videoAspectRatio: captureManager.videoPortraitAspectRatio
            )
            .ignoresSafeArea()

            StatusOverlayView(
                state: coordinator.speakerState,
                audioProb: coordinator.audioProb,
                mouthVariance: coordinator.mouthVariance
            )

            TranscriptOverlayView(text: coordinator.transcriptText)
        }
    }
}
