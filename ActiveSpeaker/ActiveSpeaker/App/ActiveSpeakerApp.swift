import SwiftUI
import MWDATCore

@main
struct ActiveSpeakerApp: App {

    @StateObject private var coordinator = PipelineCoordinator()
    @StateObject private var captureManager = CaptureManager()
    @StateObject private var gallery = FaceGallery()
    @StateObject private var glassesConnection: GlassesConnectionManager

    /// Raw wearables interface, passed directly to stream views (matches sensory pattern).
    private let wearables: WearablesInterface

    /// Lazily created embedding processor (may fail if model not bundled yet).
    @State private var embeddingProcessor: FaceEmbeddingProcessor?
    @State private var didConfigure = false

    init() {
        try? Wearables.configure()
        let w = Wearables.shared
        self.wearables = w
        _glassesConnection = StateObject(wrappedValue: GlassesConnectionManager(wearables: w))
    }

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

                GlassesView(wearables: wearables, connectionManager: glassesConnection)
                    .tabItem {
                        Label("Glasses", systemImage: "eyeglasses")
                    }
            }
            .onAppear {
                guard !didConfigure else { return }
                didConfigure = true

                let faceDetectionProvider = FaceDetectionProvider()

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
            .onOpenURL { url in
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
                else { return }
                glassesConnection.handleURL(url)
            }
        }
    }
}
