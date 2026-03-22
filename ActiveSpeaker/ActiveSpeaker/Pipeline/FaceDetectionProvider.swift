import Vision
import CoreVideo
import ImageIO

/// Shared face detection and landmarks provider.
///
/// Runs face detection + landmarks on every frame. The Neural Engine on A13+
/// handles this at 30fps. By removing the broken VNTrackObjectRequest layer
/// (which used VNImageRequestHandler instead of VNSequenceRequestHandler and
/// called perform() multiple times per handler), we eliminate the flickering
/// that occurred after ~30s of tracking drift.
///
/// Called on the video processing serial queue — not thread-safe.
final class FaceDetectionProvider {

    /// Cache the last successful detection so callers (e.g., mouth processor)
    /// always have something to work with even if a single frame fails.
    private var lastFaces: [VNFaceObservation] = []

    // MARK: - Public

    /// Detect faces and landmarks in the given pixel buffer.
    func detectFaces(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> [VNFaceObservation] {

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        do {
            try handler.perform([request])
        } catch {
            return lastFaces
        }

        guard let faces = request.results, !faces.isEmpty else {
            // Keep last result for one cycle to avoid single-frame flicker.
            let cached = lastFaces
            lastFaces = []
            return cached
        }

        lastFaces = faces
        return faces
    }

    func reset() {
        lastFaces = []
    }
}
