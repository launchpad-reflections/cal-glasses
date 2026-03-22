import SwiftUI
import AVFoundation

/// UIViewRepresentable that displays the live camera feed via AVCaptureVideoPreviewLayer
/// and draws face bounding box overlays using manual coordinate conversion.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    var faces: [IdentifiedFace] = []
    /// Portrait aspect ratio (width/height) of the video feed, e.g. 0.75 for 4:3.
    var videoAspectRatio: CGFloat = 3.0 / 4.0

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // Mirror for selfie view. The connection may not exist yet, so also
        // set it in layoutSubviews when the connection becomes available.
        view.configureMirroring()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoAspectRatio = videoAspectRatio
        uiView.updateFaces(faces)
    }

    /// Custom UIView that sizes an AVCaptureVideoPreviewLayer to fill its bounds
    /// and manages face bounding box overlay layers.
    class PreviewUIView: UIView {

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var videoAspectRatio: CGFloat = 3.0 / 4.0
        private var boxLayers: [CALayer] = []
        private var labelLayers: [CATextLayer] = []
        private var pendingFaces: [IdentifiedFace] = []
        private var didConfigureMirroring = false

        func configureMirroring() {
            guard let connection = previewLayer.connection else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            didConfigureMirroring = true
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The preview layer connection may not exist at makeUIView time.
            // Retry here until it's set.
            if !didConfigureMirroring {
                configureMirroring()
            }
            if !pendingFaces.isEmpty {
                renderFaceOverlays()
            }
        }

        func updateFaces(_ faces: [IdentifiedFace]) {
            pendingFaces = faces
            renderFaceOverlays()
        }

        private func renderFaceOverlays() {
            // Remove old overlays
            boxLayers.forEach { $0.removeFromSuperlayer() }
            labelLayers.forEach { $0.removeFromSuperlayer() }
            boxLayers.removeAll()
            labelLayers.removeAll()

            let viewW = bounds.width
            let viewH = bounds.height
            guard viewW > 0, viewH > 0, videoAspectRatio > 0 else { return }

            // Compute the full video dimensions as displayed (before aspect-fill crop).
            // The video is portrait-oriented (same as display) because the buffer is
            // mirrored+rotated to match the selfie preview.
            let viewAR = viewW / viewH
            let displayW: CGFloat
            let displayH: CGFloat
            if videoAspectRatio > viewAR {
                // Video wider than view — sides cropped
                displayH = viewH
                displayW = viewH * videoAspectRatio
            } else {
                // Video taller than view — top/bottom cropped
                displayW = viewW
                displayH = viewW / videoAspectRatio
            }
            let xOff = (displayW - viewW) / 2
            let yOff = (displayH - viewH) / 2

            for face in pendingFaces {
                // Vision rect: origin bottom-left, 0–1, portrait-oriented.
                // Convert to UIKit: origin top-left, pixels.
                let vb = face.boundingBox
                let rect = CGRect(
                    x: vb.minX * displayW - xOff,
                    y: (1 - vb.maxY) * displayH - yOff,
                    width: vb.width * displayW,
                    height: vb.height * displayH
                )

                // Bounding box
                let boxLayer = CALayer()
                boxLayer.frame = rect
                boxLayer.borderWidth = 2
                boxLayer.borderColor = (face.name == "Unknown" ? UIColor.gray : UIColor.cyan).cgColor
                boxLayer.cornerRadius = 3
                layer.addSublayer(boxLayer)
                boxLayers.append(boxLayer)

                // Label
                let textLayer = CATextLayer()
                let labelText: String
                if face.name == "Unknown" {
                    labelText = "Unknown"
                } else {
                    labelText = "\(face.name) \(Int(face.confidence * 100))%"
                }
                textLayer.string = labelText
                textLayer.fontSize = 12
                textLayer.font = UIFont.boldSystemFont(ofSize: 12)
                textLayer.foregroundColor = UIColor.white.cgColor
                textLayer.backgroundColor = (face.name == "Unknown"
                    ? UIColor.gray : UIColor.cyan
                ).withAlphaComponent(0.7).cgColor
                textLayer.alignmentMode = .center
                textLayer.contentsScale = UIScreen.main.scale
                textLayer.cornerRadius = 4
                let labelWidth = max(rect.width, 80)
                textLayer.frame = CGRect(
                    x: rect.midX - labelWidth / 2,
                    y: rect.minY - 22,
                    width: labelWidth,
                    height: 18
                )
                layer.addSublayer(textLayer)
                labelLayers.append(textLayer)
            }
        }
    }
}
