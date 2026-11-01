import AVFoundation

/// Mac side of the call-audio bridge: Mac mic -> phone (frame type 3, PCM16 mono 16 kHz), phone mic -> Mac speakers.
/// Voice processing on the input gives echo cancellation, which matters because the phone's mic hears our own voice back.
final class AudioBridge: ObservableObject {
    static let shared = AudioBridge()
    @Published var state = "off" // off | waiting | live
    @Published var level = 0.0   // phone mic level 0..1 — shows whether Android is feeding us real audio or silence

    private var engine: AVAudioEngine?
    private let player = AVAudioPlayerNode()
    private let play16 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let wire16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var pending = 0

    func start(source: String = "mic") {
        state = "waiting"
        Link.shared.sendMessage(["t": "audio_start", "src": source])
        AVCaptureDevice.requestAccess(for: .audio) { ok in if ok { DispatchQueue.main.async { self.startEngine() } } else { DispatchQueue.main.async { self.state = "off" } } }
    }

    func stop(notifyPhone: Bool = true) {
        if notifyPhone { Link.shared.sendMessage(["t": "audio_stop"]) }
        engine?.inputNode.removeTap(onBus: 0); player.stop(); engine?.stop(); engine = nil
        state = "off"; level = 0
    }

    private func startEngine() {
        let e = AVAudioEngine(); engine = e
        try? e.inputNode.setVoiceProcessingEnabled(true) // AEC + noise suppression
        e.attach(player); e.connect(player, to: e.mainMixerNode, format: play16)
        let inFmt = e.inputNode.outputFormat(forBus: 0)
        guard let conv = AVAudioConverter(from: inFmt, to: wire16) else { return }
        e.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { [weak self] buf, _ in
            guard let self, let out = AVAudioPCMBuffer(pcmFormat: self.wire16, frameCapacity: 4096) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            guard out.frameLength > 0, let p = out.int16ChannelData?[0] else { return }
            Link.shared.sendAudio(Data(bytes: p, count: Int(out.frameLength) * 2))
        }
        e.prepare()
        do { try e.start(); player.play() } catch { NSLog("audio engine: \(error)"); state = "off" }
    }

    /// Phone -> Mac frame ([3][PCM16]).
    func play(_ d: Data) {
        guard state != "off", d.count > 1 else { return }
        let n = (d.count - 1) / 2
        guard pending < 12, let buf = AVAudioPCMBuffer(pcmFormat: play16, frameCapacity: AVAudioFrameCount(n)) else { return } // >240 ms queued: drop, stay live
        buf.frameLength = AVAudioFrameCount(n)
        d.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self).baseAddress!.advanced(by: 0)
            // payload starts after the 1-byte type; load unaligned
            for i in 0..<n { buf.floatChannelData![0][i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 1 + i * 2, as: Int16.self))) / 32768 }
            _ = s
        }
        pending += 1
        player.scheduleBuffer(buf) { DispatchQueue.main.async { self.pending -= 1 } }
    }
}
