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

            VStack {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .shadow(radius: 4)
                    .padding(.top, 8)

                Spacer()
            }

            StatusOverlayView(
                state: coordinator.speakerState,
                audioProb: coordinator.audioProb,
                mouthVariance: coordinator.mouthVariance
            )

            TranscriptOverlayView(text: coordinator.transcriptText)
        }
    }
}
