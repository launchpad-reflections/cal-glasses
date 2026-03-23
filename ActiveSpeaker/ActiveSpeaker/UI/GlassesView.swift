import MWDATCore
import SwiftUI

/// Top-level glasses tab. Mirrors sensory's MainAppView pattern exactly:
/// simple if/else that swaps between HomeView and StreamView.
struct GlassesView: View {

    let wearables: WearablesInterface
    @ObservedObject var connectionManager: GlassesConnectionManager
    @ObservedObject var coordinator: PipelineCoordinator
    @ObservedObject var gallery: FaceGallery

    var body: some View {
        if connectionManager.connectionState == .registered ||
           connectionManager.connectionState == .streaming {
            GlassesStreamView(wearables: wearables,
                              connectionManager: connectionManager,
                              coordinator: coordinator,
                              gallery: gallery)
        } else {
            GlassesHomeView(connectionManager: connectionManager)
        }
    }
}

// MARK: - Home View (disconnected/registering/error states)

private struct GlassesHomeView: View {

    @ObservedObject var connectionManager: GlassesConnectionManager

    var body: some View {
        NavigationView {
            Group {
                switch connectionManager.connectionState {
                case .registering:
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Connecting...").font(.headline)
                        Text("Complete the pairing in the Meta AI app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .error(let msg):
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48)).foregroundColor(.orange)
                        Text(msg).font(.body).multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                        Button("Try Again") { connectionManager.connect() }
                            .buttonStyle(.borderedProminent).padding(.bottom, 40)
                    }
                default:
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: "eyeglasses")
                            .font(.system(size: 64)).foregroundStyle(.secondary)
                        Text("Connect Meta Ray-Ban Glasses").font(.headline)
                        Text("You'll be redirected to the Meta AI app to pair.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                        Spacer()
                        Button("Connect Glasses") { connectionManager.connect() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Glasses")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Error", isPresented: $connectionManager.showError) {
            Button("OK") { connectionManager.dismissError() }
        } message: {
            Text(connectionManager.errorMessage)
        }
    }
}

// MARK: - Stream View

private struct GlassesStreamView: View {

    @StateObject private var streamVM: GlassesStreamManager
    @ObservedObject var connectionManager: GlassesConnectionManager
    @ObservedObject var coordinator: PipelineCoordinator
    let gallery: FaceGallery

    init(wearables: WearablesInterface,
         connectionManager: GlassesConnectionManager,
         coordinator: PipelineCoordinator,
         gallery: FaceGallery) {
        self._streamVM = StateObject(wrappedValue: GlassesStreamManager(wearables: wearables))
        self.connectionManager = connectionManager
        self.coordinator = coordinator
        self.gallery = gallery
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live video feed
            if let frame = streamVM.currentFrame, streamVM.hasReceivedFirstFrame {
                GeometryReader { geometry in
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else if streamVM.streamStatus == "Waiting..." {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to glasses...")
                        .font(.caption).foregroundColor(.white)
                }
            }

            // Speaker state border overlay
            if streamVM.isStreaming {
                Rectangle()
                    .stroke(coordinator.speakerState.color, lineWidth: 6)
                    .ignoresSafeArea()
            }

            // Controls + info overlay
            VStack {
                // Top bar: speaker state + disconnect
                HStack(alignment: .top) {
                    if streamVM.isStreaming {
                        Text(coordinator.speakerState.displayText)
                            .font(.headline.bold())
                            .foregroundColor(coordinator.speakerState.color)
                            .shadow(color: .black.opacity(0.6), radius: 2, x: 1, y: 1)
                    }
                    Spacer()
                    Button {
                        connectionManager.disconnect()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                // Identified faces
                if streamVM.isStreaming && !coordinator.identifiedFaces.isEmpty {
                    HStack {
                        ForEach(coordinator.identifiedFaces) { face in
                            if face.name != "Unknown" {
                                Text("\(face.name) \(Int(face.confidence * 100))%")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.cyan.opacity(0.7))
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Transcript
                if streamVM.isStreaming && !coordinator.transcriptText.isEmpty {
                    Text(coordinator.transcriptText)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                // Bottom controls
                VStack(spacing: 12) {
                    if streamVM.isStreaming {
                        // Debug info
                        Text(String(format: "Audio: %.2f  Mouth: %.6f",
                                    coordinator.audioProb, coordinator.mouthVariance))
                            .font(.caption2.monospaced())
                            .foregroundColor(.white.opacity(0.6))

                        Button {
                            Task { await streamVM.stopStreaming() }
                        } label: {
                            Text("Stop Streaming")
                                .font(.headline)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(.red)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    } else if streamVM.streamStatus == "Stopped" {
                        Button {
                            Task { await streamVM.startStreaming() }
                        } label: {
                            Text("Start Streaming")
                                .font(.headline)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(streamVM.hasActiveDevice ? .blue : .gray)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .disabled(!streamVM.hasActiveDevice)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .alert("Streaming Error", isPresented: $streamVM.showError) {
            Button("OK") { streamVM.dismissError() }
        } message: {
            Text(streamVM.errorMessage)
        }
        .onAppear {
            // Wire up the pipeline coordinator to the stream manager
            streamVM.coordinator = coordinator
        }
        .onDisappear {
            Task {
                if streamVM.isStreaming {
                    await streamVM.stopStreaming()
                }
            }
        }
    }
}
