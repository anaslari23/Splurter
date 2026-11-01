import AVFoundation

/// Mac side of the call-audio bridge: Mac mic -> phone (frame type 3, PCM16 mono 16 kHz), phone mic -> Mac speakers.
/// Voice processing on the input gives echo cancellation, which matters because the phone's mic hears our own voice back.
final class AudioBridge: ObservableObject {
    static let shared = AudioBridge()
    @Published var state = "off" // off | waiting | live
    @Published var level = 0.0   // phone mic level 0..1 — shows whether Android is feeding us real audio or silence

    private var capture: AVAudioEngine?   // Mac mic -> phone (voice processing: noise suppression / AEC)
    private var playback: AVAudioEngine?  // phone mic -> Mac speakers
    private let player = AVAudioPlayerNode()
    private let play16 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let wire16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var pending = 0
    private var sent = 0, got = 0
    private var talkingUntil = Date.distantPast // half-duplex echo guard, see play()

    func start(source: String = "mic") {
        state = "waiting"; Debug.log("audio: start requested")
        Link.shared.sendMessage(["t": "audio_start", "src": source])
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            Debug.log("audio: mic permission \(ok)")
            DispatchQueue.main.async { ok ? self.startEngines() : { self.state = "off" }() }
        }
    }

    func stop(notifyPhone: Bool = true) {
        if notifyPhone { Link.shared.sendMessage(["t": "audio_stop"]) }
        capture?.inputNode.removeTap(onBus: 0); capture?.stop(); capture = nil
        player.stop(); playback?.stop(); playback = nil
        state = "off"; level = 0
    }

    // ponytail: macOS 27 refuses to start voice processing together with playback (-10875 on the output unit), so capture
    // and playback are separate engines and echo is handled by the half-duplex guard instead of true AEC.
    private func startEngines() {
        let pe = AVAudioEngine(); playback = pe
        pe.attach(player); pe.connect(player, to: pe.mainMixerNode, format: play16)

        let ce = AVAudioEngine(); capture = ce
        do { try ce.inputNode.setVoiceProcessingEnabled(true) } catch { Debug.log("audio: VP unavailable \(error)") }
        let inFmt = ce.inputNode.outputFormat(forBus: 0)
        Debug.log("audio: input format \(inFmt)")
        guard let conv = AVAudioConverter(from: inFmt, to: wire16) else { return }
        ce.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { [weak self] buf, _ in
            guard let self, let out = AVAudioPCMBuffer(pcmFormat: self.wire16, frameCapacity: 4096) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            guard out.frameLength > 0, let p = out.int16ChannelData?[0] else { return }
            let n = Int(out.frameLength)
            var sum = 0.0; for i in 0..<n { let v = Double(p[i]) / 32768; sum += v * v }
            if (sum / Double(n)).squareRoot() > 0.015 { self.talkingUntil = Date().addingTimeInterval(0.4) } // we're speaking
            self.sent += 1; if self.sent % 100 == 1 { Debug.log("audio: sent \(self.sent) frames to phone") }
            Link.shared.sendAudio(Data(bytes: p, count: n * 2))
        }
        do {
            try pe.start(); player.play()
            try ce.start()
            Debug.log("audio: engines running")
        } catch { Debug.log("audio: engine failed \(error)"); stop() }
    }

    /// Phone -> Mac frame ([3][PCM16]).
    func play(_ d: Data) {
        got += 1; if got % 100 == 1 { Debug.log("audio: received \(got) frames from phone, state=\(state)") }
        guard state != "off", d.count > 1, Date() > talkingUntil else { return } // muted while you speak: the phone mic would send your voice back as echo
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
