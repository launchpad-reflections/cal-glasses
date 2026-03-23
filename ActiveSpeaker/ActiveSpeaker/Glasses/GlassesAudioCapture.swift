import AVFoundation

/// Captures audio from Meta glasses microphone via HFP Bluetooth,
/// resamples to 16kHz mono Float32 PCM.
///
/// HFP streams at 8kHz mono. This service must be started *before*
/// the StreamSession so HFP is fully configured first.
final class GlassesAudioCapture {

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16000
    private var converter: AVAudioConverter?

    private let lock = NSLock()
    private var buffer: [Float] = []

    var isRunning: Bool { engine.isRunning }

    /// Configure AVAudioSession for HFP Bluetooth (glasses mic).
    /// Call before starting the MWDAT stream session.
    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Start capturing from the HFP Bluetooth microphone.
    func start() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            self?.handleBuffer(pcmBuffer, outputFormat: outputFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    /// Drain all accumulated samples since last call.
    func drain() -> Data? {
        lock.lock()
        guard !buffer.isEmpty else {
            lock.unlock()
            return nil
        }
        let samples = buffer
        buffer.removeAll(keepingCapacity: true)
        lock.unlock()

        return samples.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
    }

    private func handleBuffer(_ inputBuffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = targetSampleRate / inputBuffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if error != nil { return }
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let count = Int(outputBuffer.frameLength)

        lock.lock()
        buffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        lock.unlock()
    }
}
