import AVFoundation
import CoreML

/// Audio processor that runs Silero VAD via CoreML.
///
/// The Silero model is a stateful RNN. Each inference receives:
/// - input: [1, 576] = 64 context samples + 512 new samples
/// - state: [2, 1, 128] RNN hidden state
/// - sr: sample rate (16000)
/// And produces:
/// - output: [1, 1] speech probability
/// - stateOut: [2, 1, 128] updated hidden state
final class SileroVADProcessor: AudioProcessor {

    let name = "sileroVAD"

    private let sampleRate: Int = 16000
    private let chunkSize: Int = 512
    private let contextSize: Int = 64

    // CoreML model
    private var model: MLModel?

    // Stateful inference
    private var state: MLMultiArray
    private var context: [Float]

    // Pre-allocated input arrays (reused each inference)
    private let inputArray: MLMultiArray
    private let srArray: MLMultiArray

    // Accumulation buffer for when tap delivers non-512 buffers
    private var accumulator: [Float] = []

    init() {
        // Pre-allocate arrays
        state = Self.makeStateArray()
        context = [Float](repeating: 0, count: 64)

        inputArray = try! MLMultiArray(shape: [1, 576], dataType: .float32)
        srArray = try! MLMultiArray(shape: [1], dataType: .int32)
        srArray[0] = NSNumber(value: 16000)

        loadModel()
    }

    // MARK: - AudioProcessor

    func process(buffer: AVAudioPCMBuffer) -> Float {
        guard let model else { return 0.0 }
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        accumulator.append(contentsOf: samples)

        // Process all complete chunks
        var lastProb: Float = 0.0
        while accumulator.count >= chunkSize {
            let chunk = Array(accumulator.prefix(chunkSize))
            accumulator.removeFirst(chunkSize)
            lastProb = runInference(chunk: chunk, model: model)
        }

        return lastProb
    }

    func reset() {
        state = Self.makeStateArray()
        context = [Float](repeating: 0, count: contextSize)
        accumulator.removeAll()
    }

    // MARK: - Model loading

    private func loadModel() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly

        // Look for compiled model in bundle
        guard let modelURL = Bundle.main.url(forResource: "SileroVAD", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "SileroVAD", withExtension: "mlpackage") else {
            print("[SileroVAD] Model not found in bundle — VAD disabled")
            return
        }

        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            print("[SileroVAD] Failed to load model: \(error)")
        }
    }

    // MARK: - Inference

    private func runInference(chunk: [Float], model: MLModel) -> Float {
        // Fill input: [context (64) | chunk (512)] = 576 samples
        let inputPtr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: 576)
        for i in 0..<contextSize {
            inputPtr[i] = context[i]
        }
        for i in 0..<chunkSize {
            inputPtr[contextSize + i] = chunk[i]
        }

        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(multiArray: inputArray),
            "state": MLFeatureValue(multiArray: state),
            "sr": MLFeatureValue(multiArray: srArray),
        ])

        guard let provider,
              let prediction = try? model.prediction(from: provider) else {
            return 0.0
        }

        // Update state
        if let newState = prediction.featureValue(for: "stateOut")?.multiArrayValue {
            state = newState
        }

        // Update context — last 64 samples of the chunk
        context = Array(chunk.suffix(contextSize))

        // Extract probability
        if let output = prediction.featureValue(for: "output")?.multiArrayValue {
            return output[0].floatValue
        }

        return 0.0
    }

    // MARK: - Helpers

    private static func makeStateArray() -> MLMultiArray {
        let arr = try! MLMultiArray(shape: [2, 1, 128], dataType: .float32)
        let ptr = arr.dataPointer.bindMemory(to: Float.self, capacity: 256)
        for i in 0..<256 { ptr[i] = 0.0 }
        return arr
    }
}
