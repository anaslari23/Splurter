import AVFoundation
import SwiftUI

/// Receives H.264 (Annex-B) frames from the phone and shows them in an AVSampleBufferDisplayLayer,
/// which decodes in hardware. Frame = [kind: 0 SPS/PPS, 1 key, 2 delta][Annex-B bytes].
final class Mirror: ObservableObject {
    static let shared = Mirror()
    let layer = AVSampleBufferDisplayLayer()
    @Published var state = "idle" // idle | waiting | live | denied | stopped
    @Published var aspect: CGFloat = 9.0 / 16.0
    private var format: CMVideoFormatDescription?

    private init() { layer.videoGravity = .resizeAspect }

    func feed(_ d: Data) { // called on the link queue
        guard d.count > 2 else { return }
        let nals = Self.nalUnits(Data(d.dropFirst(2)))
        if d[1] == 0 {
            guard let sps = nals.first(where: { $0.first.map { $0 & 0x1f } == 7 }),
                  let pps = nals.first(where: { $0.first.map { $0 & 0x1f } == 8 }) else { return }
            var fd: CMVideoFormatDescription?
            let a = [UInt8](sps), b = [UInt8](pps)
            a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in
                let ptrs = [pa.baseAddress!, pb.baseAddress!]; let sizes = [a.count, b.count]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: ptrs,
                                                                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
            } }
            format = fd
            return
        }
        guard let format else { return }
        var avcc = Data()
        for n in nals where [1, 5].contains(n.first.map { $0 & 0x1f } ?? 0) { // slices only; SPS/PPS/AUD are out-of-band
            avcc += withUnsafeBytes(of: UInt32(n.count).bigEndian) { Data($0) } + n
        }
        guard !avcc.isEmpty, let sb = Self.sample(avcc, format) else { return }
        if layer.sampleBufferRenderer.status == .failed { layer.sampleBufferRenderer.flush() }
        layer.sampleBufferRenderer.enqueue(sb)
    }

    private static func sample(_ avcc: Data, _ fmt: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: avcc.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        _ = avcc.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count) }
        var sb: CMSampleBuffer?; var size = avcc.count
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: fmt, sampleCount: 1, sampleTimingEntryCount: 1,
                                  sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sb)
        if let sb, let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
           CFArrayGetCount(att) > 0 { // show as soon as decoded — we want latency, not smooth pacing
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(att, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }

    /// Splits an Annex-B stream on 00 00 01 / 00 00 00 01 start codes.
    static func nalUnits(_ d: Data) -> [Data] {
        let b = [UInt8](d); var starts: [(pos: Int, len: Int)] = []; var i = 0
        while i + 3 <= b.count {
            if b[i] == 0, b[i + 1] == 0 {
                if b[i + 2] == 1 { starts.append((i, 3)); i += 3; continue }
                if i + 3 < b.count, b[i + 2] == 0, b[i + 3] == 1 { starts.append((i, 4)); i += 4; continue }
            }
            i += 1
        }
        return starts.enumerated().map { k, s in Data(b[(s.pos + s.len)..<(k + 1 < starts.count ? starts[k + 1].pos : b.count)]) }
    }
}

struct MirrorView: View {
    @ObservedObject var mirror = Mirror.shared

    var body: some View {
        ZStack {
            Color.black
            LayerView(layer: mirror.layer)
            if mirror.state != "live" {
                VStack(spacing: 10) {
                    if mirror.state == "waiting" || mirror.state == "idle" { ProgressView().controlSize(.large) }
                    Text(message).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                }.padding()
            }
        }
        .frame(minWidth: 240, minHeight: 420)
        .aspectRatio(mirror.aspect, contentMode: .fit)
        .onDisappear { Link.shared.sendMessage(["t": "mirror_stop"]); mirror.state = "idle" }
    }

    private var message: String {
        switch mirror.state {
        case "denied": return "Screen sharing was declined on the phone"
        case "stopped": return "Screen sharing stopped"
        default: return "Tap the notification on your phone\nand choose “Start now”"
        }
    }
}

struct LayerView: NSViewRepresentable {
    let layer: CALayer
    func makeNSView(context: Context) -> NSView { let v = NSView(); v.layer = layer; v.wantsLayer = true; return v }
    func updateNSView(_ v: NSView, context: Context) {}
}
