import UIKit
import Accelerate

/// Deduplicates frames using perceptual hashing.
/// Groups similar frames and keeps the sharpest from each group.
enum FrameDeduplicator {

    /// Deduplicate an array of frames, returning 5-10 unique representative images.
    static func deduplicate(_ frames: [UIImage], maxOutput: Int = 8) -> [UIImage] {
        guard frames.count > maxOutput else { return frames }

        // Compute perceptual hash for each frame
        let hashes = frames.map { perceptualHash($0) }

        // Group frames by similarity (hamming distance < threshold)
        var groups: [[Int]] = []
        var assigned = Set<Int>()

        for i in 0..<frames.count {
            guard !assigned.contains(i) else { continue }
            var group = [i]
            assigned.insert(i)

            for j in (i + 1)..<frames.count {
                guard !assigned.contains(j) else { continue }
                if hammingDistance(hashes[i], hashes[j]) < 12 {
                    group.append(j)
                    assigned.insert(j)
                }
            }
            groups.append(group)
        }

        // From each group, pick the sharpest frame
        var result: [(image: UIImage, sharpness: Double)] = []
        for group in groups {
            let best = group
                .map { (index: $0, sharpness: laplacianVariance(frames[$0])) }
                .max(by: { $0.sharpness < $1.sharpness })!
            result.append((image: frames[best.index], sharpness: best.sharpness))
        }

        // Sort by sharpness descending, take top maxOutput
        result.sort { $0.sharpness > $1.sharpness }
        let output = Array(result.prefix(maxOutput).map(\.image))
        NSLog("[FrameDedup] \(frames.count) frames → \(groups.count) groups → \(output.count) unique")
        return output
    }

    // MARK: - Perceptual Hash

    /// 64-bit perceptual hash: resize to 8x8 grayscale, compare each pixel to mean.
    private static func perceptualHash(_ image: UIImage) -> UInt64 {
        guard let cgImage = image.cgImage else { return 0 }

        let size = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: size * size)

        guard let context = CGContext(
            data: &pixels,
            width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var hash: UInt64 = 0
        for (i, pixel) in pixels.enumerated() {
            if pixel > UInt8(mean) {
                hash |= (1 << i)
            }
        }
        return hash
    }

    /// Hamming distance between two 64-bit hashes.
    private static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Sharpness (Laplacian Variance)

    /// Estimate image sharpness using variance of Laplacian.
    private static func laplacianVariance(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }

        let width = min(cgImage.width, 128)
        let height = min(cgImage.height, 128)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Simple Laplacian: sum of |4*center - neighbors|
        var sum: Double = 0
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let top = Double(pixels[(y - 1) * width + x])
                let bottom = Double(pixels[(y + 1) * width + x])
                let left = Double(pixels[y * width + (x - 1)])
                let right = Double(pixels[y * width + (x + 1)])
                let laplacian = abs(4 * center - top - bottom - left - right)
                sum += laplacian * laplacian
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }
}
