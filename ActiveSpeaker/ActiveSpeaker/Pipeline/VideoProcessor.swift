import CoreVideo
import ImageIO

/// Protocol for video processing stages in the pipeline.
///
/// Conforming types receive pixel buffers and return a scalar signal value.
/// Called on a dedicated serial queue — implementations need not be thread-safe.
protocol VideoProcessor: AnyObject {
    var name: String { get }
    func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Float
    func reset()
}
