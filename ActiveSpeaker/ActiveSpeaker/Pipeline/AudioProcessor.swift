import AVFoundation

/// Protocol for audio processing stages in the pipeline.
///
/// Conforming types receive audio buffers and return a scalar signal value.
/// Called on a dedicated serial queue — implementations need not be thread-safe.
protocol AudioProcessor: AnyObject {
    var name: String { get }
    func process(buffer: AVAudioPCMBuffer) -> Float
    func reset()
}
