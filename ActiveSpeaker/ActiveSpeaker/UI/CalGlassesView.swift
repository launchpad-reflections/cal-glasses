import MWDATCore
import SwiftUI

/// Single-screen Cal Reflections UI: connect glasses → stream → log food → see results.
struct CalGlassesView: View {

    let wearables: WearablesInterface
    @ObservedObject var connectionManager: GlassesConnectionManager
    @ObservedObject var coordinator: PipelineCoordinator

    var body: some View {
        if connectionManager.connectionState == .registered ||
           connectionManager.connectionState == .streaming {
            CalStreamView(wearables: wearables,
                          connectionManager: connectionManager,
                          coordinator: coordinator)
        } else {
            CalHomeView(connectionManager: connectionManager)
        }
    }
}

// MARK: - Home View

private struct CalHomeView: View {

    @ObservedObject var connectionManager: GlassesConnectionManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("Cal Reflections")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Text("Log calories hands-free with your Meta glasses.")
                        .font(.body)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 16) {
                    if connectionManager.connectionState == .registering {
                        ProgressView()
                            .tint(.white)
                        Text("Connecting...")
                            .font(.headline)
                            .foregroundColor(.white)
                    } else if case .error(let msg) = connectionManager.connectionState {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Text("You'll be redirected to the Meta AI app.")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 24)

                    Button {
                        connectionManager.connect()
                    } label: {
                        Text(connectionManager.connectionState == .registering
                             ? "Connecting..." : "Connect Glasses")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(connectionManager.connectionState == .registering
                                        ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(connectionManager.connectionState == .registering)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .alert("Error", isPresented: $connectionManager.showError) {
            Button("OK") { connectionManager.dismissError() }
        } message: {
            Text(connectionManager.errorMessage)
        }
    }
}

// MARK: - Stream View

private struct CalStreamView: View {

    @StateObject private var streamVM: GlassesStreamManager
    @ObservedObject var connectionManager: GlassesConnectionManager
    @ObservedObject var coordinator: PipelineCoordinator

    init(wearables: WearablesInterface,
         connectionManager: GlassesConnectionManager,
         coordinator: PipelineCoordinator) {
        self._streamVM = StateObject(wrappedValue: GlassesStreamManager(wearables: wearables))
        self.connectionManager = connectionManager
        self.coordinator = coordinator
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live video
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
                    ProgressView().tint(.white)
                    Text("Connecting to glasses...")
                        .font(.caption).foregroundColor(.white)
                }
            }

            // Recording border
            if case .recording = streamVM.foodLoggingState {
                Rectangle()
                    .stroke(Color.red, lineWidth: 6)
                    .ignoresSafeArea()
            }

            // Overlay
            VStack {
                // Top bar
                HStack(alignment: .top) {
                    // Transcript
                    if streamVM.isStreaming && !coordinator.transcriptText.isEmpty {
                        Text(coordinator.transcriptText)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .lineLimit(2)
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

                Spacer()

                // Recording countdown
                if case .recording(let secondsLeft) = streamVM.foodLoggingState {
                    VStack(spacing: 8) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                            .symbolEffect(.pulse)
                        Text("Logging food... \(secondsLeft)s")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                        Text("Look at your food and describe what you're eating")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Processing spinner
                if streamVM.foodLoggingState == .processing {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white).scaleEffect(1.5)
                        Text("Analyzing food...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Results
                if streamVM.foodLoggingState == .results, let results = streamVM.foodResults {
                    FoodResultsOverlay(results: results) {
                        streamVM.dismissResults()
                    }
                }

                // Bottom controls
                VStack(spacing: 12) {
                    if streamVM.isStreaming && streamVM.foodLoggingState == .idle {
                        Text("Say \"log food\" or tap below")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))

                        Button {
                            streamVM.manualTriggerFoodLogging()
                        } label: {
                            Label("Log Food", systemImage: "fork.knife")
                                .font(.headline)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(.green)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    } else if streamVM.streamStatus == "Stopped" {
                        Button {
                            Task { await streamVM.startStreaming() }
                        } label: {
                            Text("Start Glasses")
                                .font(.headline)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(streamVM.hasActiveDevice ? .green : .gray)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .disabled(!streamVM.hasActiveDevice)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .alert("Error", isPresented: $streamVM.showError) {
            Button("OK") { streamVM.dismissError() }
        } message: {
            Text(streamVM.errorMessage)
        }
        .onAppear {
            streamVM.coordinator = coordinator
        }
        .onChange(of: coordinator.foodLoggingTriggered) { _, triggered in
            if triggered && streamVM.foodLoggingState == .idle {
                streamVM.startFoodLogging()
            }
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

// MARK: - Food Results Overlay

private struct FoodResultsOverlay: View {
    let results: FoodAnalysisResult
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Food Detected")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }

            if results.items.isEmpty {
                Text("No food detected. Try again.")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(results.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: iconForType(item.type))
                                    .foregroundColor(colorForType(item.type))
                                Text(item.name)
                                    .font(.body.bold())
                                    .foregroundColor(.white)
                            }
                            Text(item.quantity)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        if item.hasNutritionLabel {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        Text("\(Int(item.confidence * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func iconForType(_ type: FoodItem.FoodItemType) -> String {
        switch type {
        case .packaged: return "shippingbox.fill"
        case .dish: return "fork.knife"
        case .drink: return "cup.and.saucer.fill"
        }
    }

    private func colorForType(_ type: FoodItem.FoodItemType) -> Color {
        switch type {
        case .packaged: return .orange
        case .dish: return .yellow
        case .drink: return .cyan
        }
    }
}
