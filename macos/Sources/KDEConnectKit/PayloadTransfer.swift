import Foundation
import NIOCore
import NIOFoundationCompat
import NIOPosix
import NIOSSL
import NIOTLS

/// What to send as a payload.
public enum PayloadSource: Sendable {
    case file(URL)
    case data(Data)
}

/// Payloads (files, notification icons) travel on their own TLS connection. The sender opens a
/// server on a port in 1739–1764 and names it in the packet; the receiver connects to it and is
/// the TLS client. Both ends must present the certificates of the linked devices.
extension LanLinkProvider {
    struct Upload {
        let port: Int
        let size: Int64
        let completion: EventLoopFuture<Void>
    }

    func startUpload(_ source: PayloadSource, for link: DeviceLink,
                     progress: (@Sendable (Int64, Int64) -> Void)?) async throws -> Upload
    {
        let reader = try PayloadReader(source)
        let eventLoop = group.next()
        let done = eventLoop.makePromise(of: Void.self)
        let pinned = link.certificateDER
        let tls = self.tls
        let claimed = NIOLockedBool()

        var bound: Channel?
        for port in Self.payloadPorts {
            let bootstrap = ServerBootstrap(group: eventLoop)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        // One transfer per server: refuse anyone after the first connection.
                        guard claimed.claim() else { throw LinkError.transferTimedOut }
                        let verify: NIOSSLCustomVerificationCallback = { certificates, promise in
                            let der = try? certificates.first?.toDERBytes()
                            promise.succeed(der == pinned ? .certificateVerified : .failed)
                        }
                        try channel.pipeline.syncOperations.addHandlers(
                            NIOSSLServerHandler(context: tls.server, customVerificationCallback: verify),
                            PayloadSender(reader: reader, progress: progress, done: done)
                        )
                    }
                }
            if let channel = try? await bootstrap.bind(host: "0.0.0.0", port: port).get() {
                bound = channel
                break
            }
        }
        guard let server = bound, let port = server.localAddress?.port else {
            reader.close()
            throw LinkError.noFreePort
        }

        // Give the peer a minute to start; stop listening once the transfer ends either way.
        let timeout = eventLoop.scheduleTask(in: .seconds(60)) {
            if !claimed.isClaimed { done.fail(LinkError.transferTimedOut) }
        }
        done.futureResult.whenComplete { _ in
            timeout.cancel()
            server.close(promise: nil)
            reader.close()
        }
        // The server is not needed once the one connection has been accepted.
        return Upload(port: port, size: reader.size, completion: done.futureResult)
    }

    func download(from host: String, port: Int, size: Int64, link: DeviceLink, to file: URL?,
                  progress: (@Sendable (Int64, Int64) -> Void)?) async throws -> Data?
    {
        let eventLoop = group.next()
        let done = eventLoop.makePromise(of: Data?.self)
        let pinned = link.certificateDER
        let tls = self.tls

        var handle: FileHandle?
        if let file {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            handle = try FileHandle(forWritingTo: file)
        }
        let receiver = PayloadReceiver(expected: size, file: handle, progress: progress, done: done)

        do {
            _ = try await ClientBootstrap(group: eventLoop)
                .connectTimeout(.seconds(10))
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let verify: NIOSSLCustomVerificationCallback = { certificates, promise in
                            let der = try? certificates.first?.toDERBytes()
                            promise.succeed(der == pinned ? .certificateVerified : .failed)
                        }
                        try channel.pipeline.syncOperations.addHandlers(
                            NIOSSLClientHandler(context: tls.client, serverHostname: nil, customVerificationCallback: verify),
                            receiver
                        )
                    }
                }
                .connect(host: host, port: port)
                .get()
        } catch {
            try? handle?.close()
            throw error
        }
        defer { try? handle?.close() }
        return try await done.futureResult.get()
    }
}

/// A flag that exactly one caller can set.
final class NIOLockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value { return false }
        value = true
        return true
    }

    var isClaimed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Reads a payload in chunks.
final class PayloadReader: @unchecked Sendable {
    let size: Int64
    private var handle: FileHandle?
    private var data: Data?
    private var offset = 0

    init(_ source: PayloadSource) throws {
        switch source {
        case .file(let url):
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            handle = try FileHandle(forReadingFrom: url)
        case .data(let data):
            size = Int64(data.count)
            self.data = data
        }
    }

    func next(maxLength: Int) throws -> Data? {
        if let handle {
            let chunk = try handle.read(upToCount: maxLength) ?? Data()
            return chunk.isEmpty ? nil : chunk
        }
        guard let data, offset < data.count else { return nil }
        let end = min(offset + maxLength, data.count)
        defer { offset = end }
        return data.subdata(in: offset..<end)
    }

    func close() {
        try? handle?.close()
        handle = nil
    }
}

/// Streams a payload once TLS is up, one chunk at a time so a slow peer applies backpressure.
final class PayloadSender: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let reader: PayloadReader
    private let progress: (@Sendable (Int64, Int64) -> Void)?
    private let done: EventLoopPromise<Void>
    private var sent: Int64 = 0
    private var finished = false

    init(reader: PayloadReader, progress: (@Sendable (Int64, Int64) -> Void)?, done: EventLoopPromise<Void>) {
        self.reader = reader
        self.progress = progress
        self.done = done
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? TLSUserEvent, case .handshakeCompleted = event {
            sendNext(context: context)
        }
        context.fireUserInboundEventTriggered(event)
    }

    private func sendNext(context: ChannelHandlerContext) {
        do {
            guard let chunk = try reader.next(maxLength: 256 * 1024) else {
                finished = true
                context.close(promise: nil)
                done.succeed(())
                return
            }
            sent += Int64(chunk.count)
            let sent = self.sent
            let total = reader.size
            context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(data: chunk))).whenComplete { [self] result in
                switch result {
                case .success:
                    progress?(sent, total)
                    sendNext(context: context)
                case .failure(let error):
                    fail(error, context: context)
                }
            }
        } catch {
            fail(error, context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !finished { done.fail(LinkError.payloadTruncated(received: sent, expected: reader.size)) }
        finished = true
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error, context: context)
    }

    private func fail(_ error: Error, context: ChannelHandlerContext) {
        guard !finished else { return }
        finished = true
        done.fail(error)
        context.close(promise: nil)
    }
}

/// Receives a payload into memory or a file.
final class PayloadReceiver: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let expected: Int64
    private let file: FileHandle?
    private let progress: (@Sendable (Int64, Int64) -> Void)?
    private let done: EventLoopPromise<Data?>
    private var data = Data()
    private var received: Int64 = 0
    private var finished = false
    private var lastReport: Int64 = 0

    init(expected: Int64, file: FileHandle?, progress: (@Sendable (Int64, Int64) -> Void)?, done: EventLoopPromise<Data?>) {
        self.expected = expected
        self.file = file
        self.progress = progress
        self.done = done
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !finished else { return }
        var buffer = unwrapInboundIn(data)
        let remaining = expected >= 0 ? Int(expected - received) : buffer.readableBytes
        guard let chunk = buffer.readData(length: min(buffer.readableBytes, remaining)) else { return }
        do {
            if let file { try file.write(contentsOf: chunk) } else { self.data.append(chunk) }
        } catch {
            return fail(error, context: context)
        }
        received += Int64(chunk.count)
        if received - lastReport >= 256 * 1024 || received == expected {
            lastReport = received
            progress?(received, expected)
        }
        if expected >= 0, received >= expected {
            finished = true
            done.succeed(file == nil ? self.data : nil)
            context.close(promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !finished {
            finished = true
            if expected < 0 {
                done.succeed(file == nil ? data : nil)
            } else {
                done.fail(LinkError.payloadTruncated(received: received, expected: expected))
            }
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Peers often close without a TLS close_notify once everything is sent.
        if finished { return }
        if let sslError = error as? NIOSSLError, case .uncleanShutdown = sslError, expected >= 0, received >= expected { return }
        fail(error, context: context)
    }

    private func fail(_ error: Error, context: ChannelHandlerContext) {
        guard !finished else { return }
        finished = true
        done.fail(error)
        context.close(promise: nil)
    }
}
