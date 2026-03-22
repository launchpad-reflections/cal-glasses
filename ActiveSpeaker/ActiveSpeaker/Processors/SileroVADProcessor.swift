import AVFoundation
import onnxruntime

/// Audio processor that runs Silero VAD via ONNX Runtime (C API).
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

    // ONNX Runtime handles
    private var ortEnv: OpaquePointer?
    private var ortSession: OpaquePointer?
    private let ortApi: UnsafePointer<OrtApi>

    // Stateful inference
    private var state: [Float]
    private var context: [Float]

    // Accumulation buffer for when tap delivers non-512 buffers
    private var accumulator: [Float] = []

    init() {
        ortApi = OrtGetApiBase().pointee.GetApi(UInt32(ORT_API_VERSION))!
        state = [Float](repeating: 0, count: 2 * 1 * 128)
        context = [Float](repeating: 0, count: 64)
        loadModel()
    }

    deinit {
        if let ortSession { ortApi.pointee.ReleaseSession(ortSession) }
        if let ortEnv { ortApi.pointee.ReleaseEnv(ortEnv) }
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

        // Create environment
        var env: OpaquePointer?
        let envStatus = ortApi.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "sileroVAD", &env)
        if let envStatus {
            let msg = String(cString: ortApi.pointee.GetErrorMessage(envStatus))
            print("[SileroVAD] Failed to create env: \(msg)")
            ortApi.pointee.ReleaseStatus(envStatus)
            return
        }
        ortEnv = env

        // Create session options
        var options: OpaquePointer?
        let optStatus = ortApi.pointee.CreateSessionOptions(&options)
        if let optStatus {
            let msg = String(cString: ortApi.pointee.GetErrorMessage(optStatus))
            print("[SileroVAD] Failed to create session options: \(msg)")
            ortApi.pointee.ReleaseStatus(optStatus)
            return
        }
        defer { if let options { ortApi.pointee.ReleaseSessionOptions(options) } }

        ortApi.pointee.SetIntraOpNumThreads(options, 1)

        // Create session
        var session: OpaquePointer?
        let sessionStatus = ortApi.pointee.CreateSession(env, modelPath, options, &session)
        if let sessionStatus {
            let msg = String(cString: ortApi.pointee.GetErrorMessage(sessionStatus))
            print("[SileroVAD] Failed to create session: \(msg)")
            ortApi.pointee.ReleaseStatus(sessionStatus)
            return
        }
        ortSession = session
    }

    // MARK: - Inference

    private func runInference(chunk: [Float]) -> Float {
        guard let session = ortSession, let env = ortEnv else { return 0.0 }

        let memoryInfo = createCpuMemoryInfo()
        guard let memoryInfo else { return 0.0 }
        defer { ortApi.pointee.ReleaseMemoryInfo(memoryInfo) }

        // Build input: [context (64) | chunk (512)] = 576 samples
        var inputData = context + chunk
        var stateData = state
        var srData: [Int64] = [Int64(sampleRate)]

        // Create input tensors
        var inputTensor: OpaquePointer?
        var inputShape: [Int64] = [1, 576]
        ortApi.pointee.CreateTensorWithDataAsOrtValue(
            memoryInfo,
            &inputData, inputData.count * MemoryLayout<Float>.size,
            &inputShape, 2,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &inputTensor
        )

        var stateTensor: OpaquePointer?
        var stateShape: [Int64] = [2, 1, 128]
        ortApi.pointee.CreateTensorWithDataAsOrtValue(
            memoryInfo,
            &stateData, stateData.count * MemoryLayout<Float>.size,
            &stateShape, 3,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &stateTensor
        )

        var srTensor: OpaquePointer?
        var srShape: [Int64] = [1]
        ortApi.pointee.CreateTensorWithDataAsOrtValue(
            memoryInfo,
            &srData, srData.count * MemoryLayout<Int64>.size,
            &srShape, 1,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
            &srTensor
        )

        guard let inputTensor, let stateTensor, let srTensor else {
            return 0.0
        }
        defer {
            ortApi.pointee.ReleaseValue(inputTensor)
            ortApi.pointee.ReleaseValue(stateTensor)
            ortApi.pointee.ReleaseValue(srTensor)
        }

        // Input/output names
        let inputNames: [UnsafePointer<CChar>?] = [
            "input".withCString { UnsafePointer(strdup($0)) },
            "state".withCString { UnsafePointer(strdup($0)) },
            "sr".withCString { UnsafePointer(strdup($0)) },
        ]
        let outputNames: [UnsafePointer<CChar>?] = [
            "output".withCString { UnsafePointer(strdup($0)) },
            "stateOut".withCString { UnsafePointer(strdup($0)) },
        ]
        defer {
            for name in inputNames { free(UnsafeMutablePointer(mutating: name)) }
            for name in outputNames { free(UnsafeMutablePointer(mutating: name)) }
        }

        let inputValues: [OpaquePointer?] = [inputTensor, stateTensor, srTensor]
        var outputValues: [OpaquePointer?] = [nil, nil]

        // Run inference
        let runStatus = ortApi.pointee.Run(
            session, nil,
            inputNames, inputValues, 3,
            outputNames, 2, &outputValues
        )

        if let runStatus {
            let msg = String(cString: ortApi.pointee.GetErrorMessage(runStatus))
            print("[SileroVAD] Inference error: \(msg)")
            ortApi.pointee.ReleaseStatus(runStatus)
            return 0.0
        }

        defer {
            for val in outputValues { if let val { ortApi.pointee.ReleaseValue(val) } }
        }

        // Update state from stateOut
        if let stateOut = outputValues[1] {
            var statePtr: UnsafeMutableRawPointer?
            ortApi.pointee.GetTensorMutableData(stateOut, &statePtr)
            if let statePtr {
                let floatPtr = statePtr.assumingMemoryBound(to: Float.self)
                state = Array(UnsafeBufferPointer(start: floatPtr, count: 2 * 1 * 128))
            }
        }

        // Update context — last 64 samples of the chunk
        context = Array(chunk.suffix(contextSize))

        // Extract probability
        if let output = outputValues[0] {
            var outputPtr: UnsafeMutableRawPointer?
            ortApi.pointee.GetTensorMutableData(output, &outputPtr)
            if let outputPtr {
                return outputPtr.assumingMemoryBound(to: Float.self).pointee
            }
        }

        return 0.0
    }

    // MARK: - Helpers

    private func createCpuMemoryInfo() -> OpaquePointer? {
        var memoryInfo: OpaquePointer?
        let status = ortApi.pointee.CreateCpuMemoryInfo(
            OrtArenaAllocator, OrtMemTypeDefault, &memoryInfo
        )
        if let status {
            ortApi.pointee.ReleaseStatus(status)
            return nil
        }
        return memoryInfo
    }
}
