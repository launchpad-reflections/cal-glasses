import SwiftUI
import AVFoundation

/// UIViewRepresentable that displays the live camera feed via AVCaptureVideoPreviewLayer.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection {
            connection.isVideoMirrored = true
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    /// Custom UIView that sizes an AVCaptureVideoPreviewLayer to fill its bounds.
    class PreviewUIView: UIView {

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
