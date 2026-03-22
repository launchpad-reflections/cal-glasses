import Vision
import CoreVideo
import ImageIO

/// Detects mouth movement using Apple Vision face landmarks.
///
/// Uses a tracking hybrid: full face detection on first frame, then
/// VNTrackObjectRequest for subsequent frames with periodic re-detection.
/// Landmark extraction uses inputFaceObservations to skip detection phase.
final class MouthMovementProcessor: VideoProcessor {

    let name = "mouthMovement"

    private let apertureBuffer = RollingBuffer<Float>(capacity: 10)

    // Tracking state
    private var trackedFace: VNDetectedObjectObservation?
    private var framesSinceDetection: Int = 0
    private let redetectInterval = 30

    // MARK: - VideoProcessor

    func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        // Decide whether to run full detection or tracking
        if trackedFace == nil || framesSinceDetection >= redetectInterval {
            return runFullDetection(handler: handler)
        } else {
            return runTrackedLandmarks(handler: handler, pixelBuffer: pixelBuffer, orientation: orientation)
        }
    }

    func reset() {
        apertureBuffer.reset()
        trackedFace = nil
        framesSinceDetection = 0
    }

    // MARK: - Full face detection (every N frames)

    private func runFullDetection(handler: VNImageRequestHandler) -> Float {
        let faceRequest = VNDetectFaceLandmarksRequest()
        faceRequest.revision = VNDetectFaceLandmarksRequestRevision3

        do {
            try handler.perform([faceRequest])
        } catch {
            return appendAndComputeVariance(0.0)
        }

        guard let face = faceRequest.results?.first else {
            trackedFace = nil
            return appendAndComputeVariance(0.0)
        }

        // Update tracking state
        trackedFace = face
        framesSinceDetection = 0

        return extractMouthAperture(from: face)
    }

    // MARK: - Tracked landmark extraction (most frames)

    private func runTrackedLandmarks(
        handler: VNImageRequestHandler,
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> Float {
        guard let tracked = trackedFace else {
            return runFullDetection(handler: handler)
        }

        // Track the face bounding box
        let trackRequest = VNTrackObjectRequest(detectedObjectObservation: tracked)
        trackRequest.trackingLevel = .fast

        do {
            try handler.perform([trackRequest])
        } catch {
            trackedFace = nil
            return appendAndComputeVariance(0.0)
        }

        guard let trackResult = trackRequest.results?.first as? VNDetectedObjectObservation,
              trackResult.confidence > 0.3 else {
            // Tracking lost — force re-detection next frame
            trackedFace = nil
            return appendAndComputeVariance(0.0)
        }

        trackedFace = trackResult
        framesSinceDetection += 1

        // Run landmarks only within tracked region (skips face detection)
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        landmarksRequest.inputFaceObservations = [
            VNFaceObservation(boundingBox: trackResult.boundingBox)
        ]

        do {
            try handler.perform([landmarksRequest])
        } catch {
            return appendAndComputeVariance(0.0)
        }

        guard let face = landmarksRequest.results?.first else {
            return appendAndComputeVariance(0.0)
        }

        return extractMouthAperture(from: face)
    }

    // MARK: - Mouth aperture calculation

    private func extractMouthAperture(from face: VNFaceObservation) -> Float {
        guard let innerLips = face.landmarks?.innerLips,
              let leftEye = face.landmarks?.leftEye,
              let rightEye = face.landmarks?.rightEye else {
            return appendAndComputeVariance(0.0)
        }

        let lipPoints = innerLips.normalizedPoints
        guard lipPoints.count >= 6 else {
            return appendAndComputeVariance(0.0)
        }

        // Mouth aperture: vertical distance between top and bottom inner lip
        // Inner lip winding: points roughly go around the lip contour
        // Top-center is approximately at index count/2, bottom at index 0
        // For a 6-point inner lip: 0=left, 1=bottom-left, 2=bottom, 3=right, 4=top-right, 5=top
        let upperLip = lipPoints[lipPoints.count / 2 + lipPoints.count / 2 - 1]  // top area
        let lowerLip = lipPoints[lipPoints.count / 4]  // bottom area

        // More robust: find the topmost and bottommost points
        let topPoint = lipPoints.max(by: { $0.y < $1.y }) ?? lipPoints[0]
        let bottomPoint = lipPoints.min(by: { $0.y < $1.y }) ?? lipPoints[0]
        let mouthDist = abs(topPoint.y - bottomPoint.y)

        // Inter-eye distance for normalization
        let leftEyePoints = leftEye.normalizedPoints
        let rightEyePoints = rightEye.normalizedPoints
        guard !leftEyePoints.isEmpty, !rightEyePoints.isEmpty else {
            return appendAndComputeVariance(0.0)
        }

        // Use the medial (inner) corners of each eye
        let leftInner = leftEyePoints[leftEyePoints.count - 1]
        let rightInner = rightEyePoints[0]
        let eyeDist = hypot(rightInner.x - leftInner.x, rightInner.y - leftInner.y)

        let normalizedAperture: Float
        if eyeDist > 0.01 {
            normalizedAperture = Float(mouthDist / eyeDist)
        } else {
            normalizedAperture = 0.0
        }

        return appendAndComputeVariance(normalizedAperture)
    }

    // MARK: - Rolling variance

    private func appendAndComputeVariance(_ value: Float) -> Float {
        apertureBuffer.append(value)
        guard apertureBuffer.count >= 3 else { return 0.0 }
        return apertureBuffer.variance()
    }
}
