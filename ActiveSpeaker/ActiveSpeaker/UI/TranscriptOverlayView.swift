import SwiftUI

/// Subtitle-style overlay that displays live transcription text at the bottom of the screen.
struct TranscriptOverlayView: View {

    let text: String

    var body: some View {
        VStack {
            Spacer()

            if !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: text)
            }
        }
    }
}
