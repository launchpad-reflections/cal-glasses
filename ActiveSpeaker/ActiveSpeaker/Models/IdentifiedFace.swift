import Foundation
import CoreGraphics

/// A recognized face in the current frame with identity and location.
struct IdentifiedFace: Identifiable, Equatable {
    let id = UUID()
    let name: String        // enrolled name or "Unknown"
    let boundingBox: CGRect // Vision normalized coordinates (origin bottom-left, 0–1)
    let confidence: Float   // cosine similarity score (0–1)
}
