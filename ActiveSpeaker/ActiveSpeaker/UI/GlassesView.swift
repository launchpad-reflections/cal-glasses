import MWDATCore
import SwiftUI

/// Top-level glasses tab. Mirrors sensory's MainAppView pattern exactly:
/// simple if/else that swaps between HomeView and StreamView.
struct GlassesView: View {

    let wearables: WearablesInterface
    @ObservedObject var connectionManager: GlassesConnectionManager

    var body: some View {
        if connectionManager.connectionState == .registered ||
           connectionManager.connectionState == .streaming {
            GlassesStreamView(wearables: wearables, connectionManager: connectionManager)
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

// MARK: - Stream View (mirrors sensory's StreamView exactly)

private struct GlassesStreamView: View {

    @StateObject private var streamVM: GlassesStreamManager
    @ObservedObject var connectionManager: GlassesConnectionManager

    init(wearables: WearablesInterface, connectionManager: GlassesConnectionManager) {
        self._streamVM = StateObject(wrappedValue: GlassesStreamManager(wearables: wearables))
        self.connectionManager = connectionManager
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

            // Controls overlay
            VStack {
                // Top bar
                HStack(alignment: .top) {
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

                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    if streamVM.isStreaming {
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
        .onDisappear {
            Task {
                if streamVM.isStreaming {
                    await streamVM.stopStreaming()
                }
            }
        }
    }
}
