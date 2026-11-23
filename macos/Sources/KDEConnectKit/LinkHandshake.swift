import Foundation
import NIOCore
import NIOFoundationCompat
import NIOSSL
import NIOTLS

/// Splits the stream into `\n`-terminated packets. Remembers how far it has searched, so a
/// multi-megabyte packet (a long SMS thread) arriving in small chunks is scanned only once.
struct LineDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    var maximumLength = 64 * 1024 * 1024
    private var searched = 0

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        let view = buffer.readableBytesView
        let start = view.index(view.startIndex, offsetBy: searched)
        if let newline = view[start...].firstIndex(of: UInt8(ascii: "\n")) {
            let length = view.distance(from: view.startIndex, to: newline)
            let line = buffer.readSlice(length: length)!
            buffer.moveReaderIndex(forwardBy: 1)
            searched = 0
            context.fireChannelRead(wrapInboundOut(line))
            return .continue
        }
        searched = view.count
        if searched > maximumLength { throw LinkError.packetTooLarge }
        return .needMoreData
    }

    mutating func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        while try decode(context: context, buffer: &buffer) == .continue {}
        return .needMoreData
    }
}

/// Runs the protocol-version-8 handshake on a fresh TCP connection, then carries the packets of
/// the resulting `DeviceLink`.
///
/// 1. The side that opened the TCP connection sends a short identity in plain text.
/// 2. TLS starts, with the roles reversed: the side that *accepted* the connection is the TLS
///    client. Both sides present their self-signed certificates.
/// 3. Both sides send their full identity again, encrypted. Only that copy is trusted, and its
///    device ID must match the plain-text one and the certificate's common name.
final class LinkHandshakeHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum Direction {
        /// The peer connected to our TCP server after seeing our UDP broadcast.
        case incoming
        /// We connected to the peer after seeing its UDP broadcast.
        case outgoing(deviceId: String, protocolVersion: Int)
    }

    private enum State {
        case idle
        case awaitingConnectionPacket
        case tlsHandshake
        case awaitingIdentity
        case established(DeviceLink)
        case closed
    }

    private let provider: LanLinkProvider
    private let direction: Direction
    private var state = State.idle
    private var peerDeviceId: String?
    private var peerProtocolVersion = 0
    private var timeout: Scheduled<Void>?

    init(provider: LanLinkProvider, direction: Direction) {
        self.provider = provider
        self.direction = direction
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive { begin(context: context) }
    }

    func channelActive(context: ChannelHandlerContext) {
        begin(context: context)
        context.fireChannelActive()
    }

    private func begin(context: ChannelHandlerContext) {
        guard case .idle = state else { return }
        switch direction {
        case .incoming:
            state = .awaitingConnectionPacket
            armTimeout(context: context)
        case .outgoing(let deviceId, let protocolVersion):
            peerDeviceId = deviceId
            peerProtocolVersion = protocolVersion
            let packet = provider.identity.connectionPacket(targetDeviceId: deviceId, targetProtocolVersion: protocolVersion)
            write(packet, context: context)
            startTLS(context: context, asServer: true)
            armTimeout(context: context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let line = unwrapInboundIn(data)
        switch state {
        case .awaitingConnectionPacket:
            receiveConnectionPacket(line, context: context)
        case .awaitingIdentity:
            receiveSecureIdentity(line, context: context)
        case .established(let link):
            link.receive(line)
        case .idle, .tlsHandshake, .closed:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? TLSUserEvent, case .handshakeCompleted = event, case .tlsHandshake = state {
            state = .awaitingIdentity
            write(provider.identity.identityPacket(capabilities: provider.capabilities), context: context)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        timeout?.cancel()
        if case .established(let link) = state {
            link.finish()
            provider.linkClosed(link)
        }
        state = .closed
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        trace("errorCaught in \(state): \(error)")
        if case .established = state {
            lanLog.notice("Link error: \(String(describing: error), privacy: .public)")
        } else {
            lanLog.notice("Handshake with \(self.peerDeviceId ?? "?", privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        context.close(promise: nil)
    }

    // MARK: Steps

    private func receiveConnectionPacket(_ line: ByteBuffer, context: ChannelHandlerContext) {
        guard let packet = try? NetworkPacket(data: Data(buffer: line)), packet.type == PacketType.identity,
              let deviceId = packet["deviceId"]?.string, DeviceIdentifier.isValid(deviceId)
        else { return fail("unreadable connection packet", context: context) }

        if let target = packet["targetDeviceId"]?.string, target != provider.identity.deviceId {
            return fail("connection meant for another device", context: context)
        }
        if let target = packet["targetProtocolVersion"]?.int, target != Int64(LocalIdentity.protocolVersion) {
            return fail("connection meant for protocol \(target)", context: context)
        }
        let version = Int(packet["protocolVersion"]?.int ?? 0)
        guard version >= LocalIdentity.protocolVersion else { return fail("protocol version \(version) is too old", context: context) }
        if let trusted = provider.trust.device(deviceId), trusted.protocolVersion > version {
            return fail("refusing protocol downgrade", context: context)
        }
        guard deviceId != provider.identity.deviceId else { return fail("that's us", context: context) }

        peerDeviceId = deviceId
        peerProtocolVersion = version
        trace("incoming connection from \(packet["deviceName"]?.string ?? deviceId); starting TLS as client")
        startTLS(context: context, asServer: false)
    }

    private func startTLS(context: ChannelHandlerContext, asServer: Bool) {
        let provider = self.provider
        let deviceId = peerDeviceId
        let verify: NIOSSLCustomVerificationCallback = { certificates, promise in
            promise.succeed(provider.acceptsCertificate(certificates.first, for: deviceId) ? .certificateVerified : .failed)
        }
        do {
            let handler: ChannelHandler = asServer
                ? NIOSSLServerHandler(context: provider.tls.server, customVerificationCallback: verify)
                : try NIOSSLClientHandler(context: provider.tls.client, serverHostname: nil, customVerificationCallback: verify)
            state = .tlsHandshake
            try context.pipeline.syncOperations.addHandler(handler, position: .first)
        } catch {
            fail("could not start TLS: \(error)", context: context)
        }
    }

    private func receiveSecureIdentity(_ line: ByteBuffer, context: ChannelHandlerContext) {
        guard let packet = try? NetworkPacket(data: Data(buffer: line)), let info = PeerInfo(identity: packet) else {
            return fail("unreadable identity", context: context)
        }
        guard info.deviceId == peerDeviceId else { return fail("device ID changed during the handshake", context: context) }
        guard info.protocolVersion == peerProtocolVersion else { return fail("protocol version changed during the handshake", context: context) }

        guard let ssl = try? context.pipeline.syncOperations.handler(type: NIOSSLHandler.self),
              let certificate = ssl.peerCertificate,
              let der = try? certificate.toDERBytes(),
              let spki = try? certificate.extractPublicKey().toSPKIBytes()
        else { return fail("no peer certificate", context: context) }

        let commonName = CertificateInfo.commonName(ofDER: der).map(Self.exportable)
        guard commonName == Self.exportable(info.deviceId) else {
            return fail("certificate common name does not match the device ID", context: context)
        }

        timeout?.cancel()
        let remoteHost = context.channel.remoteAddress?.ipAddress.map(Self.unmapped)
        let link = DeviceLink(info: info, certificateDER: der, publicKeySPKI: spki, remoteHost: remoteHost,
                              channel: context.channel, provider: provider)
        state = .established(link)
        provider.linkEstablished(link)
    }

    // MARK: Helpers

    private func write(_ packet: NetworkPacket, context: ChannelHandlerContext) {
        guard let data = try? packet.serialized() else { return }
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(data: data)), promise: nil)
    }

    private func armTimeout(context: ChannelHandlerContext) {
        timeout?.cancel()
        let channel = context.channel
        timeout = context.eventLoop.scheduleTask(in: .seconds(8)) {
            lanLog.notice("Handshake timed out")
            channel.close(promise: nil)
        }
    }

    private func fail(_ reason: String, context: ChannelHandlerContext) {
        trace("fail: \(reason)")
        lanLog.notice("Rejecting connection from \(self.peerDeviceId ?? "?", privacy: .public): \(reason, privacy: .public)")
        state = .closed
        timeout?.cancel()
        context.close(promise: nil)
    }

    /// The desktop replaces anything outside `[A-Za-z0-9_]` before comparing IDs with certificates.
    private static func exportable(_ id: String) -> String {
        String(id.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" })
    }

    /// `::ffff:192.168.1.5` → `192.168.1.5`.
    static func unmapped(_ address: String) -> String {
        address.hasPrefix("::ffff:") ? String(address.dropFirst(7)) : address
    }
}
