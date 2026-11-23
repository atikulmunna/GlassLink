import Foundation
import NIOCore
import NIOFoundationCompat
import NIOPosix
import NIOSSL

/// One encoded frame of the phone's screen.
public struct MirrorFrame: Sendable {
    /// H.264 in Annex-B form (NAL units separated by start codes).
    public let data: Data
    /// Presentation time in microseconds, from the phone's encoder.
    public let presentationTime: Int64
    /// Codec configuration (SPS/PPS) rather than a picture.
    public let isConfig: Bool
    public let isKeyFrame: Bool
}

/// The phone's screen, streaming from GlassLink for Android's mirroring service.
///
/// The phone listens on a port it announces in a `glasslink.mirror` packet; we connect as the TLS
/// client, pinned to the paired phone's certificate (as for file transfers). Each frame arrives as
/// `[length: u32][presentation time µs: i64][flags: u8][H.264]`, big-endian; flag 1 = config,
/// flag 2 = key frame.
public final class MirrorStream: @unchecked Sendable {
    let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    public var isOpen: Bool { channel.isActive }

    public func close() {
        channel.close(promise: nil)
    }
}

extension DeviceLink {
    /// Connects to the phone's screen stream. `onFrame` and `onClose` are called on a network thread.
    public func openMirrorStream(port: Int,
                                 onFrame: @escaping @Sendable (MirrorFrame) -> Void,
                                 onClose: @escaping @Sendable () -> Void) async throws -> MirrorStream
    {
        guard let host = remoteHost else { throw LinkError.notConnected }
        return try await provider.openMirrorStream(host: host, port: port, link: self, onFrame: onFrame, onClose: onClose)
    }
}

extension LanLinkProvider {
    func openMirrorStream(host: String, port: Int, link: DeviceLink,
                          onFrame: @escaping @Sendable (MirrorFrame) -> Void,
                          onClose: @escaping @Sendable () -> Void) async throws -> MirrorStream
    {
        let pinned = link.certificateDER
        let tls = self.tls
        let channel = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelOption(.tcpOption(.tcp_nodelay), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let verify: NIOSSLCustomVerificationCallback = { certificates, promise in
                        let der = try? certificates.first?.toDERBytes()
                        promise.succeed(der == pinned ? .certificateVerified : .failed)
                    }
                    try channel.pipeline.syncOperations.addHandlers(
                        NIOSSLClientHandler(context: tls.client, serverHostname: nil, customVerificationCallback: verify),
                        ByteToMessageHandler(MirrorFrameDecoder()),
                        MirrorFrameHandler(onFrame: onFrame, onClose: onClose)
                    )
                }
            }
            .connect(host: host, port: port)
            .get()
        return MirrorStream(channel: channel)
    }
}

/// Splits the stream into frames: a 13-byte header, then the H.264 bytes.
struct MirrorFrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = MirrorFrame
    static let maximumFrame = 16 * 1024 * 1024

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes >= 13,
              let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self)
        else { return .needMoreData }
        guard Int(length) <= Self.maximumFrame else { throw LinkError.packetTooLarge }
        guard buffer.readableBytes >= 13 + Int(length) else { return .needMoreData }
        buffer.moveReaderIndex(forwardBy: 4)
        let time = buffer.readInteger(as: Int64.self) ?? 0
        let flags = buffer.readInteger(as: UInt8.self) ?? 0
        let data = buffer.readData(length: Int(length)) ?? Data()
        context.fireChannelRead(wrapInboundOut(MirrorFrame(data: data, presentationTime: time,
                                                           isConfig: flags & 1 != 0, isKeyFrame: flags & 2 != 0)))
        return .continue
    }

    mutating func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        while try decode(context: context, buffer: &buffer) == .continue {}
        return .needMoreData
    }
}

final class MirrorFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = MirrorFrame

    private let onFrame: @Sendable (MirrorFrame) -> Void
    private let onClose: @Sendable () -> Void

    init(onFrame: @escaping @Sendable (MirrorFrame) -> Void, onClose: @escaping @Sendable () -> Void) {
        self.onFrame = onFrame
        self.onClose = onClose
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        onFrame(unwrapInboundIn(data))
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        trace("mirror stream error: \(error)")
        context.close(promise: nil)
    }
}
