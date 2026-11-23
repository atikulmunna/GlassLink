import AppKit
import AVFoundation
import CoreMedia
import KDEConnectKit
import SwiftUI

/// Phone screen mirroring (GlassLink for Android), like Phone Link's: the Mac asks, the phone shows
/// Android's sharing prompt, and the screen streams back as H.264. Clicks, drags and scrolling are
/// sent back as touches.
@MainActor
@Observable
final class MirrorController {
    enum State: Equatable {
        case idle
        /// Waiting for the user to tap Start on the phone's sharing prompt.
        case asking
        case connecting
        case streaming
        case declined
        case ended(String)
    }

    private(set) var state = State.idle
    /// Size of the shared picture, in pixels (changes when the phone rotates).
    private(set) var videoSize = CGSize(width: 9, height: 19.5)
    /// The phone can't be controlled until GlassLink's accessibility service is on.
    private(set) var inputUnavailable = false

    @ObservationIgnored let renderer = H264Renderer()
    @ObservationIgnored private weak var device: PhoneDevice?
    @ObservationIgnored private var stream: MirrorStream?

    init(device: PhoneDevice) {
        self.device = device
        renderer.onSize = { [weak self] size in
            Task { @MainActor in self?.videoSize = size }
        }
    }

    var isActive: Bool { [.asking, .connecting, .streaming].contains(state) }

    func start() {
        guard let device, device.isReady, !isActive else { return }
        inputUnavailable = false // re-checked on the first touch
        state = .asking
        device.send(NetworkPacket(type: PacketType.glasslinkMirrorRequest, body: ["start": true]))
    }

    func stop() {
        if isActive { device?.send(NetworkPacket(type: PacketType.glasslinkMirrorRequest, body: ["start": false])) }
        stream?.close()
        stream = nil
        renderer.reset()
        state = .idle
    }

    func linkLost() {
        stream?.close()
        stream = nil
        if isActive { state = .ended("The phone disconnected.") }
    }

    func receive(_ packet: NetworkPacket) {
        switch packet["state"]?.string {
        case "ready":
            guard let port = packet["port"]?.int, let link = device?.link else { return }
            if let w = packet["width"]?.double, let h = packet["height"]?.double, w > 0, h > 0 {
                videoSize = CGSize(width: w, height: h)
            }
            connect(link: link, port: Int(port))
        case "denied":
            stream?.close()
            state = .declined
        case "stopped", "failed":
            stream?.close()
            stream = nil
            if isActive { state = .ended(packet["state"]?.string == "failed" ? "Screen sharing couldn't start." : "The phone stopped sharing.") }
        case "noInput":
            inputUnavailable = true
        default:
            break
        }
    }

    private func connect(link: DeviceLink, port: Int) {
        state = .connecting
        renderer.reset()
        let renderer = self.renderer
        renderer.onFirstFrame = { [weak self] in
            Task { @MainActor in if self?.state == .connecting { self?.state = .streaming } }
        }
        Task {
            do {
                stream = try await link.openMirrorStream(port: port, onFrame: { frame in
                    renderer.enqueue(frame)
                }, onClose: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.state == .streaming || self.state == .connecting else { return }
                        self.state = .ended("The phone stopped sharing.")
                    }
                })
            } catch {
                state = .ended("Couldn't connect to the phone's screen.")
            }
        }
    }

    // MARK: Touches (positions are fractions of the phone's screen)

    func tap(_ p: CGPoint) { input("tap", p) }
    func longPress(_ p: CGPoint) { input("longpress", p) }
    func swipe(from a: CGPoint, to b: CGPoint, duration: TimeInterval) {
        input("swipe", a, extra: ["x2": .double(Double(b.x)), "y2": .double(Double(b.y)), "duration": .int(Int64(duration * 1000))])
    }
    func back() { input("back", nil) }
    func home() { input("home", nil) }
    func recents() { input("recents", nil) }

    private func input(_ action: String, _ p: CGPoint?, extra: [String: JSONValue] = [:]) {
        guard state == .streaming else { return }
        var body: [String: JSONValue] = ["action": .string(action)]
        if let p { body["x"] = .double(Double(p.x)); body["y"] = .double(Double(p.y)) }
        body.merge(extra) { _, new in new }
        device?.send(NetworkPacket(type: PacketType.glasslinkMirrorInput, body: body))
    }
}

/// Decodes the H.264 stream into a display layer (hardware decoding, via AVFoundation).
final class H264Renderer: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()
    var onSize: ((CGSize) -> Void)?
    var onFirstFrame: (() -> Void)?

    private let queue = DispatchQueue(label: "glasslink.mirror.decode")
    private var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    private var shownFirst = false

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
    }

    func reset() {
        queue.async {
            self.format = nil
            self.sps = nil
            self.pps = nil
            self.shownFirst = false
            self.layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    func enqueue(_ frame: MirrorFrame) {
        queue.async { self.decode(frame) }
    }

    private func decode(_ frame: MirrorFrame) {
        var slices: [Data] = []
        for nal in Self.nalUnits(frame.data) {
            switch nal.first.map({ $0 & 0x1F }) {
            case 7: sps = nal
            case 8: pps = nal
            case 9: break // access unit delimiter
            default: slices.append(nal)
            }
        }
        if frame.isConfig || format == nil, let sps, let pps { makeFormat(sps: sps, pps: pps) }
        guard let format, !slices.isEmpty else { return }

        // AVCC: each NAL unit prefixed with its 4-byte length.
        var avcc = Data()
        for nal in slices {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }
        guard let sample = Self.sampleBuffer(avcc, format: format) else { return }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
        if !shownFirst {
            shownFirst = true
            onFirstFrame?()
        }
    }

    private func makeFormat(sps: Data, pps: Data) {
        var newFormat: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers = [spsBytes.bindMemory(to: UInt8.self).baseAddress!, ppsBytes.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &newFormat)
            }
        }
        guard status == noErr, let newFormat else { return }
        let old = format.map(CMVideoFormatDescriptionGetDimensions)
        let new = CMVideoFormatDescriptionGetDimensions(newFormat)
        format = newFormat
        if old?.width != new.width || old?.height != new.height {
            let size = CGSize(width: CGFloat(new.width), height: CGFloat(new.height))
            DispatchQueue.main.async { self.onSize?(size) }
        }
    }

    private static func sampleBuffer(_ data: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: data.count, flags: 0, blockBufferOut: &block) == noErr,
              let block
        else { return nil }
        let copied = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var size = data.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample
        else { return nil }
        // Show each frame as soon as it's decoded: this is live, not a movie.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    /// NAL units of an Annex-B stream (split at 00 00 01 / 00 00 00 01 start codes).
    static func nalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var units: [Data] = []
        var start: Int?
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                if let s = start {
                    var end = i
                    if end > s, bytes[end - 1] == 0 { end -= 1 } // 4-byte start code
                    if end > s { units.append(Data(bytes[s..<end])) }
                }
                start = i + 3
                i += 3
            } else {
                i += 1
            }
        }
        if let s = start, s < bytes.count { units.append(Data(bytes[s...])) }
        return units
    }
}

/// The video, plus mouse and trackpad handling: click = tap, hold = long press, drag = swipe,
/// two-finger scroll = swipe, right-click = Back.
struct MirrorVideoView: NSViewRepresentable {
    var controller: MirrorController

    func makeNSView(context: Context) -> MirrorNSView {
        let view = MirrorNSView()
        view.controller = controller
        view.wantsLayer = true
        view.layer?.addSublayer(controller.renderer.layer)
        return view
    }

    func updateNSView(_ view: MirrorNSView, context: Context) {
        view.controller = controller
        view.videoSize = controller.videoSize
        view.needsLayout = true
    }
}

final class MirrorNSView: NSView {
    weak var controller: MirrorController?
    var videoSize = CGSize(width: 9, height: 19.5)
    private var downPoint: CGPoint?
    private var downLocation: CGPoint = .zero
    private var downTime = Date()
    private var scrollTotal = CGSize.zero
    private var scrollAnchor: CGPoint?
    private var scrollFlush: DispatchWorkItem?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Drags here are swipes on the phone, never window moves.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controller?.renderer.layer.frame = bounds
        CATransaction.commit()
    }

    override func resetCursorRects() {
        addCursorRect(videoRect, cursor: .pointingHand)
    }

    /// Where the picture sits inside the view (aspect fit).
    private var videoRect: CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return bounds }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// A point in the view as fractions of the phone's screen (nil outside the picture).
    private func fraction(_ event: NSEvent) -> CGPoint? {
        let p = convert(event.locationInWindow, from: nil)
        let r = videoRect
        guard r.contains(p) else { return nil }
        return CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = fraction(event)
        downLocation = convert(event.locationInWindow, from: nil)
        downTime = Date()
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = downPoint else { return }
        downPoint = nil
        let location = convert(event.locationInWindow, from: nil)
        let held = Date().timeIntervalSince(downTime)
        if hypot(location.x - downLocation.x, location.y - downLocation.y) < 6 {
            held > 0.5 ? controller?.longPress(start) : controller?.tap(start)
        } else {
            let r = videoRect
            let end = CGPoint(x: min(1, max(0, (location.x - r.minX) / r.width)), y: min(1, max(0, (location.y - r.minY) / r.height)))
            controller?.swipe(from: start, to: end, duration: min(1.2, max(0.08, held)))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.back()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let point = fraction(event) ?? scrollAnchor else { return }
        if scrollAnchor == nil { scrollAnchor = point }
        let r = videoRect
        // Natural scrolling: content follows the fingers, so the "finger" on the phone moves the same way.
        scrollTotal.width += event.scrollingDeltaX / r.width
        scrollTotal.height += event.scrollingDeltaY / r.height
        scrollFlush?.cancel()
        let flush = DispatchWorkItem { [weak self] in self?.sendScroll() }
        scrollFlush = flush
        let finished = event.phase == .ended || event.momentumPhase == .ended
        DispatchQueue.main.asyncAfter(deadline: .now() + (finished ? 0 : 0.12), execute: flush)
    }

    private func sendScroll() {
        guard let anchor = scrollAnchor, abs(scrollTotal.width) + abs(scrollTotal.height) > 0.01 else {
            scrollAnchor = nil
            scrollTotal = .zero
            return
        }
        let end = CGPoint(x: min(0.98, max(0.02, anchor.x + scrollTotal.width)), y: min(0.98, max(0.02, anchor.y + scrollTotal.height)))
        controller?.swipe(from: anchor, to: end, duration: 0.25)
        scrollAnchor = nil
        scrollTotal = .zero
    }
}
