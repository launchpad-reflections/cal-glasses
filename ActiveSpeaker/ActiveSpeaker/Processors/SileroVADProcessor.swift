import AVFoundation
import OnnxRuntimeBindings

/// Audio processor that runs Silero VAD via ONNX Runtime (Obj-C API).
///
/// The Silero model is a stateful RNN. Each inference receives:
/// - input: [1, 576] = 64 context samples + 512 new samples
/// - state: [2, 1, 128] RNN hidden state
/// - sr: sample rate (16000)
/// And produces:
/// - output: [1, 1] speech probability
/// - stateN: [2, 1, 128] updated hidden state
final class SileroVADProcessor: AudioProcessor {

    let name = "sileroVAD"

    private let sampleRate: Int = 16000
    private let chunkSize: Int = 512
    private let contextSize: Int = 64
    private let stateCount = 2 * 1 * 128

    // ONNX Runtime handles
    private var ortEnv: ORTEnv?
    private var ortSession: ORTSession?

    // Stateful inference
    private var stateData: NSMutableData
    private var context: [Float]

    // Accumulation buffer for when tap delivers non-512 buffers
    private var accumulator: [Float] = []

    init() {
        stateData = NSMutableData(length: 2 * 1 * 128 * MemoryLayout<Float>.size)!
        context = [Float](repeating: 0, count: 64)
        loadModel()
    }

    // MARK: - AudioProcessor

    func process(buffer: AVAudioPCMBuffer) -> Float {
        guard ortSession != nil else { return 0.0 }
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        accumulator.append(contentsOf: samples)

        // Process all complete chunks
        var lastProb: Float = 0.0
        while accumulator.count >= chunkSize {
            let chunk = Array(accumulator.prefix(chunkSize))
            accumulator.removeFirst(chunkSize)
            lastProb = runInference(chunk: chunk)
        }

        return lastProb
    }

    func reset() {
        stateData = NSMutableData(length: stateCount * MemoryLayout<Float>.size)!
        context = [Float](repeating: 0, count: contextSize)
        accumulator.removeAll()
    }

    // MARK: - Model loading

    private func loadModel() {
        guard let modelPath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") else {
            print("[SileroVAD] silero_vad.onnx not found in bundle — VAD disabled")
            return
        }

        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let opts = try ORTSessionOptions()
            try opts.setIntraOpNumThreads(1)
            let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
            ortEnv = env
            ortSession = session
        } catch {
            print("[SileroVAD] Failed to load model: \(error)")
        }
    }

    // MARK: - Inference

    private func runInference(chunk: [Float]) -> Float {
        guard let session = ortSession else { return 0.0 }

        // Build input: [context (64) | chunk (512)] = 576 samples
        var inputArray = context + chunk
        let inputData = NSMutableData(bytes: &inputArray, length: inputArray.count * MemoryLayout<Float>.size)

        var srValue: Int64 = Int64(sampleRate)
        let srData = NSMutableData(bytes: &srValue, length: MemoryLayout<Int64>.size)

        do {
            let inputTensor = try ORTValue(
                tensorData: inputData,
                elementType: .float,
                shape: [1, 576]
            )

            let stateTensor = try ORTValue(
                tensorData: stateData,
                elementType: .float,
                shape: [2, 1, 128]
            )

            let srTensor = try ORTValue(
                tensorData: srData,
                elementType: .int64,
                shape: []
            )

            let inputs: [String: ORTValue] = [
                "input": inputTensor,
                "state": stateTensor,
                "sr": srTensor,
            ]

            let outputNames: Set<String> = ["output", "stateN"]

            let outputs = try session.run(
                withInputs: inputs,
                outputNames: outputNames,
                runOptions: nil
            )

            // Update state from stateN
            if let stateN = outputs["stateN"] {
                let newStateData = try stateN.tensorData()
                stateData = NSMutableData(data: newStateData as Data)
            }

            // Update context — last 64 samples of the chunk
            context = Array(chunk.suffix(contextSize))

            // Extract probability
            if let output = outputs["output"] {
                let outputData = try output.tensorData()
                return outputData.bytes.assumingMemoryBound(to: Float.self).pointee
            }
        } catch {
            print("[SileroVAD] Inference error: \(error)")
        }

        return 0.0
    }
}
