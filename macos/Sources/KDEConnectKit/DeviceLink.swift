import Foundation
import NIOCore
import NIOFoundationCompat

/// An encrypted, authenticated connection to one device.
///
/// Incoming packets arrive in order on `packets`; the stream ends when the connection closes.
/// `send` may be called from any thread.
public final class DeviceLink: @unchecked Sendable, Identifiable {
    public let id = UUID()
    public let info: PeerInfo
    public let certificateDER: [UInt8]
    public let publicKeySPKI: [UInt8]
    /// The peer's IP address, used to fetch payloads from it.
    public let remoteHost: String?
    public let packets: AsyncStream<NetworkPacket>

    let channel: Channel
    unowned let provider: LanLinkProvider
    private let continuation: AsyncStream<NetworkPacket>.Continuation

    init(info: PeerInfo, certificateDER: [UInt8], publicKeySPKI: [UInt8], remoteHost: String?, channel: Channel,
         provider: LanLinkProvider)
    {
        self.info = info
        self.certificateDER = certificateDER
        self.publicKeySPKI = publicKeySPKI
        self.remoteHost = remoteHost
        self.channel = channel
        self.provider = provider
        (packets, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public var deviceId: String { info.deviceId }
    public var isOpen: Bool { channel.isActive }

    /// Fire-and-forget send.
    public func send(_ packet: NetworkPacket) {
        guard let data = try? packet.serialized() else { return }
        trace("→ \(info.name): \(packet.type)")
        channel.writeAndFlush(channel.allocator.buffer(data: data), promise: nil)
    }

    /// Sends and waits until the packet has been handed to the socket.
    public func sendAndWait(_ packet: NetworkPacket) async throws {
        guard channel.isActive else { throw LinkError.notConnected }
        let data = try packet.serialized()
        try await channel.writeAndFlush(channel.allocator.buffer(data: data)).get()
    }

    public func close() {
        channel.close(promise: nil)
    }

    // MARK: Payloads

    /// Sends `packet` with a payload, waiting until the peer has downloaded all of it.
    public func send(_ packet: NetworkPacket, payload: PayloadSource,
                     progress: (@Sendable (_ sent: Int64, _ total: Int64) -> Void)? = nil) async throws
    {
        guard channel.isActive else { throw LinkError.notConnected }
        let upload = try await provider.startUpload(payload, for: self, progress: progress)
        var packet = packet
        packet.payloadSize = upload.size
        packet.payloadTransferInfo = ["port": .int(Int64(upload.port))]
        try await sendAndWait(packet)
        try await upload.completion.get()
    }

    /// Fetches the payload announced by `packet`, into memory or straight to a file.
    @discardableResult
    public func downloadPayload(of packet: NetworkPacket, to file: URL? = nil,
                                progress: (@Sendable (_ received: Int64, _ total: Int64) -> Void)? = nil) async throws -> Data?
    {
        guard let port = packet.payloadPort, let host = remoteHost else { throw LinkError.notConnected }
        return try await provider.download(from: host, port: port, size: packet.payloadSize ?? -1, link: self,
                                           to: file, progress: progress)
    }

    // MARK: Called by the channel handler

    func receive(_ line: ByteBuffer) {
        guard line.readableBytes > 0 else { return }
        do {
            let packet = try NetworkPacket(data: Data(buffer: line))
            trace("← \(info.name): \(packet.description)")
            continuation.yield(packet)
        } catch {
            lanLog.notice("Dropping malformed packet from \(self.info.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func finish() {
        continuation.finish()
    }
}
