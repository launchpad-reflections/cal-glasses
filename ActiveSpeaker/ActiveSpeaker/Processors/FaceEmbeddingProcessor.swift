import CoreML
import Vision
import CoreImage
import CoreVideo
import Accelerate

/// Generates face embeddings via MobileFaceNet (CoreML on ANE) and matches
/// them against enrolled gallery embeddings using cosine similarity.
///
/// Called on the video processing serial queue — not thread-safe.
final class FaceEmbeddingProcessor {

    private let model: MLModel
    private let gallery: FaceGallery
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Cosine similarity threshold — below this, face is labeled "Unknown".
    var similarityThreshold: Float = 0.5

    /// Run identity matching every N frames (reuse last results on skipped frames).
    var identityInterval: Int = 3
    private var frameCounter: Int = 0
    private var cachedResults: [IdentifiedFace] = []

    // MARK: - Init

    init(gallery: FaceGallery) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Prefer ANE

        guard let modelURL = Bundle.main.url(
            forResource: "MobileFaceNet",
            withExtension: "mlmodelc"
        ) else {
            throw FaceEmbeddingError.modelNotFound
        }

        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.gallery = gallery
    }

    // MARK: - Public

    /// Identify faces in the current frame against the enrolled gallery.
    /// Returns an IdentifiedFace for each detected face.
    func identify(
        faces: [VNFaceObservation],
        in pixelBuffer: CVPixelBuffer
    ) -> [IdentifiedFace] {
        frameCounter += 1

        guard !faces.isEmpty else {
            cachedResults = []
            return []
        }

        // Throttle: only run embedding on identity interval frames
        if frameCounter % identityInterval != 0 {
            // Update bounding boxes from current tracking, keep cached names
            return updateBoundingBoxes(faces: faces)
        }

        let gallerySnapshot = gallery.snapshot()
        guard !gallerySnapshot.isEmpty else {
            // No enrollments — return faces as Unknown
            cachedResults = faces.map {
                IdentifiedFace(name: "Unknown", boundingBox: $0.boundingBox, confidence: 0)
            }
            return cachedResults
        }

        var results: [IdentifiedFace] = []

        for face in faces {
            guard let embedding = extractEmbedding(
                from: pixelBuffer, boundingBox: face.boundingBox
            ) else {
                results.append(IdentifiedFace(
                    name: "Unknown", boundingBox: face.boundingBox, confidence: 0
                ))
                continue
            }

            let (name, similarity) = matchAgainstGallery(
                embedding: embedding, gallery: gallerySnapshot
            )

            results.append(IdentifiedFace(
                name: name, boundingBox: face.boundingBox, confidence: similarity
            ))
        }

        cachedResults = results
        return results
    }

    /// Generate a single embedding for enrollment (no gallery matching).
    func generateEmbedding(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) -> [Float]? {
        return extractEmbedding(from: pixelBuffer, boundingBox: boundingBox)
    }

    // MARK: - Embedding Extraction

    private func extractEmbedding(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) -> [Float]? {
        // Crop and preprocess face
        guard let faceImage = cropFace(
            from: pixelBuffer, boundingBox: boundingBox
        ) else { return nil }

        // Create MLMultiArray input [1, 3, 112, 112]
        guard let inputArray = preprocessFace(faceImage) else { return nil }

        // Run inference
        let inputName = "input"
        guard let provider = try? MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(multiArray: inputArray)]
        ) else { return nil }

        guard let prediction = try? model.prediction(from: provider) else {
            return nil
        }

        // Extract embedding from output
        return extractOutputEmbedding(from: prediction)
    }

    private func extractOutputEmbedding(from prediction: MLFeatureProvider) -> [Float]? {
        // Find the embedding output (name varies by model export)
        for name in prediction.featureNames {
            if let multiArray = prediction.featureValue(for: name)?.multiArrayValue {
                let count = multiArray.count
                guard count > 1 else { continue }

                var embedding = [Float](repeating: 0, count: count)
                let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count {
                    embedding[i] = ptr[i]
                }

                // L2-normalize the embedding
                var norm: Float = 0
                vDSP_svesq(embedding, 1, &norm, vDSP_Length(count))
                norm = sqrt(norm)
                if norm > 1e-8 {
                    var invNorm = 1.0 / norm
                    vDSP_vsmul(embedding, 1, &invNorm, &embedding, 1, vDSP_Length(count))
                }

                return embedding
            }
        }
        return nil
    }

    // MARK: - Face Cropping & Preprocessing

    private func cropFace(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) -> CGImage? {
        // Orient the CIImage to match Vision's coordinate space (portrait, mirrored).
        // The raw buffer is landscape and un-mirrored; applying .leftMirrored
        // rotates + mirrors it to match the orientation we pass to VNImageRequestHandler.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(.leftMirrored)

        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height

        // Convert Vision normalized coords to pixel coords
        // Vision: origin bottom-left, 0–1 range
        var faceRect = CGRect(
            x: boundingBox.origin.x * imageWidth + ciImage.extent.origin.x,
            y: boundingBox.origin.y * imageHeight + ciImage.extent.origin.y,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )

        // Expand by 20% for context (forehead, chin)
        let expandX = faceRect.width * 0.2
        let expandY = faceRect.height * 0.2
        faceRect = faceRect.insetBy(dx: -expandX, dy: -expandY)

        // Clamp to image bounds
        faceRect = faceRect.intersection(ciImage.extent)

        guard !faceRect.isEmpty else { return nil }

        let cropped = ciImage.cropped(to: faceRect)

        // Resize to 112x112
        let scaleX = 112.0 / faceRect.width
        let scaleY = 112.0 / faceRect.height
        let resized = cropped
            .transformed(by: CGAffineTransform(
                translationX: -faceRect.origin.x,
                y: -faceRect.origin.y
            ))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return ciContext.createCGImage(resized, from: CGRect(x: 0, y: 0, width: 112, height: 112))
    }

    private func preprocessFace(_ cgImage: CGImage) -> MLMultiArray? {
        guard cgImage.width == 112, cgImage.height == 112 else { return nil }

        // Render to RGBA pixel data
        let bytesPerPixel = 4
        let bytesPerRow = 112 * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: 112 * 112 * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: 112,
            height: 112,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 112, height: 112))

        // Create MLMultiArray with ANE-compatible 64-byte aligned strides.
        // Stride for the innermost dimension (W=112) must be padded to a
        // multiple of 64/sizeof(Float) = 16, so stride = 112 rounded up = 112
        // (already multiple of 16). But channel stride (H*W) needs alignment too.
        // Use MLShapedArray which handles alignment correctly.
        let hw = 112 * 112
        let totalElements = 3 * hw
        var floatData = [Float](repeating: 0, count: totalElements)

        for y in 0..<112 {
            for x in 0..<112 {
                let srcIdx = y * 112 * bytesPerPixel + x * bytesPerPixel
                let dstIdx = y * 112 + x

                // R, G, B channels — normalize to [-1, 1]
                floatData[0 * hw + dstIdx] = (Float(pixelData[srcIdx + 0]) / 255.0 - 0.5) / 0.5
                floatData[1 * hw + dstIdx] = (Float(pixelData[srcIdx + 1]) / 255.0 - 0.5) / 0.5
                floatData[2 * hw + dstIdx] = (Float(pixelData[srcIdx + 2]) / 255.0 - 0.5) / 0.5
            }
        }

        let shaped = MLShapedArray<Float>(scalars: floatData, shape: [1, 3, 112, 112])
        return MLMultiArray(shaped)
    }

    // MARK: - Gallery Matching

    private func matchAgainstGallery(
        embedding: [Float],
        gallery: [String: [[Float]]]
    ) -> (String, Float) {
        var bestName = "Unknown"
        var bestSimilarity: Float = 0

        for (name, embeddings) in gallery {
            for enrolled in embeddings {
                let sim = cosineSimilarity(embedding, enrolled)
                if sim > bestSimilarity {
                    bestSimilarity = sim
                    bestName = name
                }
            }
        }

        if bestSimilarity < similarityThreshold {
            return ("Unknown", bestSimilarity)
        }

        return (bestName, bestSimilarity)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 1e-8 else { return 0 }

        return dot / denom
    }

    // MARK: - Bounding Box Update (non-identity frames)

    private func updateBoundingBoxes(faces: [VNFaceObservation]) -> [IdentifiedFace] {
        // On non-identity frames, match cached results to current faces by
        // proximity and preserve the identity labels.
        guard !cachedResults.isEmpty else {
            return faces.map {
                IdentifiedFace(name: "Unknown", boundingBox: $0.boundingBox, confidence: 0)
            }
        }

        var results: [IdentifiedFace] = []

        for face in faces {
            // Find the closest cached face by bounding box center distance
            let center = CGPoint(
                x: face.boundingBox.midX,
                y: face.boundingBox.midY
            )

            var bestMatch: IdentifiedFace?
            var bestDist = CGFloat.greatestFiniteMagnitude

            for cached in cachedResults {
                let cachedCenter = CGPoint(
                    x: cached.boundingBox.midX,
                    y: cached.boundingBox.midY
                )
                let dist = hypot(center.x - cachedCenter.x, center.y - cachedCenter.y)
                if dist < bestDist {
                    bestDist = dist
                    bestMatch = cached
                }
            }

            if let match = bestMatch, bestDist < 0.15 {
                // Same identity, updated bounding box
                results.append(IdentifiedFace(
                    name: match.name,
                    boundingBox: face.boundingBox,
                    confidence: match.confidence
                ))
            } else {
                results.append(IdentifiedFace(
                    name: "Unknown",
                    boundingBox: face.boundingBox,
                    confidence: 0
                ))
            }
        }

        return results
    }
}

// MARK: - Errors

enum FaceEmbeddingError: Error {
    case modelNotFound
}
