import SwiftUI

/// Draws labeled bounding boxes over recognized faces on the camera preview.
struct FaceOverlayView: View {

    let faces: [IdentifiedFace]
    let previewSize: CGSize
    /// Portrait aspect ratio (width/height) of the video feed.
    let videoAspectRatio: CGFloat

    var body: some View {
        ZStack {
            ForEach(faces) { face in
                let rect = visionRectToView(face.boundingBox)

                // Bounding box
                Rectangle()
                    .stroke(
                        face.name == "Unknown" ? Color.gray : Color.cyan,
                        lineWidth: 2
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Name label above the box
                Text(labelText(face))
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        face.name == "Unknown"
                            ? Color.gray.opacity(0.7)
                            : Color.cyan.opacity(0.7)
                    )
                    .cornerRadius(4)
                    .position(
                        x: rect.midX,
                        y: rect.minY - 12
                    )
            }
        }
        .allowsHitTesting(false)
        .onChange(of: faces) { newFaces in
            guard let first = newFaces.first else { return }
            let rect = visionRectToView(first.boundingBox)
            let bb = first.boundingBox
            print("[FaceOverlay] preview=\(String(format: "%.0fx%.0f", previewSize.width, previewSize.height)) videoAR=\(String(format: "%.3f", videoAspectRatio)) vision=(\(String(format: "%.3f,%.3f %.3fx%.3f", bb.minX, bb.minY, bb.width, bb.height))) view=(\(String(format: "%.1f,%.1f %.1fx%.1f", rect.minX, rect.minY, rect.width, rect.height)))")
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert Vision normalized rect (origin bottom-left, 0–1) to
    /// view coordinates (origin top-left, pixel), accounting for the
    /// aspect-fill crop between the video feed and the view.
    private func visionRectToView(_ visionRect: CGRect) -> CGRect {
        guard previewSize.width > 0, previewSize.height > 0, videoAspectRatio > 0 else {
            return .zero
        }
        let viewAR = previewSize.width / previewSize.height

        // Compute the displayed (uncropped) video size within the view
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        if videoAspectRatio > viewAR {
            // Video is wider than view — sides are cropped
            displayHeight = previewSize.height
            displayWidth = displayHeight * videoAspectRatio
        } else {
            // Video is taller than view — top/bottom are cropped
            displayWidth = previewSize.width
            displayHeight = displayWidth / videoAspectRatio
        }

        // Offset from centering the video in the view
        let xOffset = (displayWidth - previewSize.width) / 2
        let yOffset = (displayHeight - previewSize.height) / 2

        return CGRect(
            x: visionRect.minX * displayWidth - xOffset,
            y: (1 - visionRect.maxY) * displayHeight - yOffset,
            width: visionRect.width * displayWidth,
            height: visionRect.height * displayHeight
        )
    }

    private func labelText(_ face: IdentifiedFace) -> String {
        if face.name == "Unknown" {
            return "Unknown"
        }
        let pct = Int(face.confidence * 100)
        return "\(face.name) \(pct)%"
    }
}
