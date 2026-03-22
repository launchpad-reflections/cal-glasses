import SwiftUI

@main
struct ActiveSpeakerApp: App {

    @StateObject private var coordinator = PipelineCoordinator()
    @StateObject private var captureManager = CaptureManager()
    @StateObject private var gallery = FaceGallery()

    /// Lazily created embedding processor (may fail if model not bundled yet).
    @State private var embeddingProcessor: FaceEmbeddingProcessor?
    @State private var didConfigure = false

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(
                    coordinator: coordinator,
                    captureManager: captureManager,
                    gallery: gallery
                )
                .tabItem {
                    Label("Camera", systemImage: "video")
                }

                EnrollmentView(
                    gallery: gallery,
                    captureManager: captureManager,
                    embeddingProcessor: embeddingProcessor
                )
                .tabItem {
                    Label("Enroll", systemImage: "person.crop.circle.badge.plus")
                }
            }
            .onAppear {
                guard !didConfigure else { return }
                didConfigure = true

                let faceDetectionProvider = FaceDetectionProvider()

                // Load the CoreML model off the main thread to avoid UI freeze
                DispatchQueue.global(qos: .userInitiated).async {
                    let processor = try? FaceEmbeddingProcessor(gallery: gallery)

                    DispatchQueue.main.async {
                        embeddingProcessor = processor

                        coordinator.configure(
                            audioProcessors: [SileroVADProcessor()],
                            mouthMovementProcessor: MouthMovementProcessor(),
                            transcriptionProvider: MoonshineTranscriber(),
                            faceDetectionProvider: faceDetectionProvider,
                            faceEmbeddingProcessor: processor
                        )
                        coordinator.startTranscription()
                        captureManager.coordinator = coordinator
                        captureManager.start()
                    }
                }
            }
        }
    }
}
