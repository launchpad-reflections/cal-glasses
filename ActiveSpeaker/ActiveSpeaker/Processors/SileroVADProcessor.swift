import AVFoundation
import onnxruntime_objc

/// Audio processor that runs Silero VAD via ONNX Runtime.
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

    // ONNX Runtime session
    private var session: ORTSession?

    // Stateful inference
    private var state: [Float]
    private var context: [Float]

    // Accumulation buffer for when tap delivers non-512 buffers
    private var accumulator: [Float] = []

    init() {
        state = [Float](repeating: 0, count: 2 * 1 * 128)
        context = [Float](repeating: 0, count: 64)
        loadModel()
    }

    // MARK: - AudioProcessor

    func process(buffer: AVAudioPCMBuffer) -> Float {
        guard let session else { return 0.0 }
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        accumulator.append(contentsOf: samples)

        // Process all complete chunks
        var lastProb: Float = 0.0
        while accumulator.count >= chunkSize {
            let chunk = Array(accumulator.prefix(chunkSize))
            accumulator.removeFirst(chunkSize)
            lastProb = runInference(chunk: chunk, session: session)
        }

        return lastProb
    }

    func reset() {
        state = [Float](repeating: 0, count: 2 * 1 * 128)
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
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(1)
            session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        } catch {
            print("[SileroVAD] Failed to create ONNX Runtime session: \(error)")
        }
    }

    // MARK: - Inference

    private func runInference(chunk: [Float], session: ORTSession) -> Float {
        do {
            // Build input: [context (64) | chunk (512)] = 576 samples
            var inputData = context + chunk

            let inputTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &inputData, length: inputData.count * MemoryLayout<Float>.size),
                elementType: .float,
                shape: [1, 576]
            )

            let stateTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &state, length: state.count * MemoryLayout<Float>.size),
                elementType: .float,
                shape: [2, 1, 128]
            )

            var srData: [Int64] = [Int64(sampleRate)]
            let srTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &srData, length: srData.count * MemoryLayout<Int64>.size),
                elementType: .int64,
                shape: [1]
            )

            let outputs = try session.run(
                withInputs: ["input": inputTensor, "state": stateTensor, "sr": srTensor],
                outputNames: ["output", "stateOut"],
                runOptions: nil
            )

            // Update state from stateOut
            if let stateOut = outputs["stateOut"] {
                let stateData = try stateOut.tensorData() as Data
                state = stateData.withUnsafeBytes { buf in
                    Array(buf.bindMemory(to: Float.self))
                }
            }

            // Update context — last 64 samples of the chunk
            context = Array(chunk.suffix(contextSize))

            // Extract probability
            if let output = outputs["output"] {
                let outputData = try output.tensorData() as Data
                let prob = outputData.withUnsafeBytes { buf in
                    buf.bindMemory(to: Float.self).first ?? 0.0
                }
                return prob
            }

            return 0.0
        } catch {
            print("[SileroVAD] Inference error: \(error)")
            return 0.0
        }
    }
}
