import SwiftUI

/// Overlay that displays the speaker state as a colored border, label, and debug info.
struct StatusOverlayView: View {

    let state: SpeakerState
    let audioProb: Float
    let mouthVariance: Float

    var body: some View {
        ZStack {
            // Colored border
            Rectangle()
                .stroke(state.color, lineWidth: 12)
                .ignoresSafeArea()

            VStack {
                // Status label (top-left)
                HStack {
                    Text(state.displayText)
                        .font(.title.bold())
                        .foregroundColor(state.color)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 1, y: 1)
                        .padding(.leading, 20)
                        .padding(.top, 16)
                    Spacer()
                }

                Spacer()

                // Debug info (bottom-left)
                HStack {
                    Text(String(format: "Audio: %.2f  Mouth var: %.6f", audioProb, mouthVariance))
                        .font(.caption.monospaced())
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                        .padding(.leading, 20)
                        .padding(.bottom, 16)
                    Spacer()
                }
            }
        }
        .drawingGroup()
    }
}
