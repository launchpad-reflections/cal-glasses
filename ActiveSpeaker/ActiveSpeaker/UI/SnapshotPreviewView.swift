import SwiftUI
import AVFoundation
import CoreImage

/// Lightweight camera preview that renders pixel buffer snapshots via CIContext
/// instead of creating a second AVCaptureVideoPreviewLayer (which would steal
/// the session connection from the main camera tab and cause freezes/black screen).
struct SnapshotPreviewView: UIViewRepresentable {

    let captureManager: CaptureManager

    func makeUIView(context: Context) -> SnapshotUIView {
        let view = SnapshotUIView()
        view.captureManager = captureManager
        return view
    }

    func updateUIView(_ uiView: SnapshotUIView, context: Context) {}

    class SnapshotUIView: UIView {

        weak var captureManager: CaptureManager?
        private var displayLink: CADisplayLink?
        private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        private let imageLayer = CALayer()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                layer.addSublayer(imageLayer)
                imageLayer.contentsGravity = .resizeAspectFill
                imageLayer.masksToBounds = true
                imageLayer.frame = bounds

                displayLink = CADisplayLink(target: self, selector: #selector(render))
                displayLink?.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 10, maximum: 15, preferred: 15
                )
                displayLink?.add(to: .main, forMode: .common)
            } else {
                displayLink?.invalidate()
                displayLink = nil
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            imageLayer.frame = bounds
        }

        @objc private func render() {
            guard let pb = captureManager?.latestPixelBuffer else { return }
            // Apply the same orientation as the main camera preview
            // (rotate to portrait + mirror for selfie = .leftMirrored)
            let ci = CIImage(cvPixelBuffer: pb).oriented(.leftMirrored)
            guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
            imageLayer.contents = cg
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
