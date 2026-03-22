import Vision
import CoreVideo
import ImageIO

/// Detects mouth movement from pre-detected face observations.
///
/// Receives face observations from FaceDetectionProvider (shared with
/// FaceEmbeddingProcessor to avoid duplicate Vision calls). Uses the
/// largest face for mouth aperture calculation.
final class MouthMovementProcessor {

    let name = "mouthMovement"

    private let deltaBuffer = RollingBuffer<Float>(capacity: 10)

    // EMA smoothing to filter landmark jitter before computing deltas
    private var smoothedAperture: Float?
    private let emaAlpha: Float = 0.4

    // MARK: - Processing

    /// Process pre-detected face observations and return mouth movement variance.
    /// Uses the largest face (closest to camera) for aperture calculation.
    func process(faces: [VNFaceObservation]) -> Float {
        // Pick the largest face by bounding box area
        guard let face = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return appendAndComputeVariance(0.0)
        }

        return extractMouthAperture(from: face)
    }

    func reset() {
        deltaBuffer.reset()
        smoothedAperture = nil
    }

    // MARK: - Mouth aperture calculation

    private func extractMouthAperture(from face: VNFaceObservation) -> Float {
        guard let innerLips = face.landmarks?.innerLips,
              let outerLips = face.landmarks?.outerLips else {
            return appendAndComputeVariance(0.0)
        }

        let innerPts = innerLips.normalizedPoints
        let outerPts = outerLips.normalizedPoints
        guard innerPts.count >= 6, outerPts.count >= 6 else {
            return appendAndComputeVariance(0.0)
        }

        // Sort inner lip points by Y to average top/bottom clusters
        let sortedByY = innerPts.sorted { $0.y < $1.y }
        let k = max(2, innerPts.count / 3)
        let bottomAvgY = sortedByY.prefix(k).map(\.y).reduce(0, +) / CGFloat(k)
        let topAvgY = sortedByY.suffix(k).map(\.y).reduce(0, +) / CGFloat(k)
        let verticalOpen = topAvgY - bottomAvgY

        // Horizontal aperture from outer lip
        let sortedByX = outerPts.sorted { $0.x < $1.x }
        let mouthWidth = sortedByX.last!.x - sortedByX.first!.x

        guard mouthWidth > 0.01 else {
            return appendAndComputeVariance(0.0)
        }

        let aspectRatio = Float(verticalOpen / mouthWidth)
        return appendAndComputeVariance(aspectRatio)
    }

    // MARK: - Rolling variance

    private func appendAndComputeVariance(_ value: Float) -> Float {
        let smoothed: Float
        if let prev = smoothedAperture {
            smoothed = emaAlpha * value + (1 - emaAlpha) * prev
        } else {
            smoothed = value
        }
        let delta = abs(smoothed - (smoothedAperture ?? smoothed))
        smoothedAperture = smoothed

        deltaBuffer.append(delta)
        guard deltaBuffer.count >= 3 else { return 0.0 }
        return deltaBuffer.variance()
    }
}
