import SwiftUI
import MWDATCore

@main
struct ActiveSpeakerApp: App {

    @StateObject private var coordinator = PipelineCoordinator()
    @StateObject private var glassesConnection: GlassesConnectionManager

    private let wearables: WearablesInterface

    init() {
        try? Wearables.configure()
        let w = Wearables.shared
        self.wearables = w
        _glassesConnection = StateObject(wrappedValue: GlassesConnectionManager(wearables: w))
    }

    var body: some Scene {
        WindowGroup {
            CalGlassesView(wearables: wearables,
                           connectionManager: glassesConnection,
                           coordinator: coordinator)
            .onAppear {
                // Configure pipeline with just VAD + transcription (no face detection needed)
                coordinator.configure(
                    audioProcessors: [SileroVADProcessor()],
                    transcriptionProvider: MoonshineTranscriber()
                )
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
