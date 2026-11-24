import Darwin
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationCompat
import NIOPosix
import NIOSSL

/// Finds devices on the local network and keeps one `DeviceLink` per device.
///
/// Discovery is symmetric: every device listens on UDP 1716 and broadcasts a small identity
/// packet there. Whoever hears a broadcast opens a TCP connection to the `tcpPort` it names, so
/// a phone that opens the KDE Connect app finds this Mac and vice versa.
public final class LanLinkProvider: @unchecked Sendable {
    public static let udpPort = 1716
    static let tcpPorts = 1716...1764
    static let payloadPorts = 1739...1764

    public let capabilities: Capabilities
    public let trust: TrustStore
    let tls: TLSContexts
    let group: MultiThreadedEventLoopGroup

    /// Called on a network thread whenever a device link is established (or replaced).
    public var onLink: (@Sendable (DeviceLink) -> Void)?

    private struct State {
        var identity: LocalIdentity
        var links: [String: DeviceLink] = [:]
        var lastAttempt: [String: Date] = [:]
        var customHosts: [String] = []
        var udp: Channel?
        var tcp: Channel?
        var tcpPort = LanLinkProvider.udpPort
        var stopping = false
        var lastSocketRefresh = Date.distantPast
    }

    private let state: NIOLockedValueBox<State>

    public init(identity: LocalIdentity, capabilities: Capabilities, trust: TrustStore) throws {
        self.capabilities = capabilities
        self.trust = trust
        self.tls = try TLSContexts(identity: identity)
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.state = NIOLockedValueBox(State(identity: identity))
    }

    deinit {
        // The last reference can be dropped on an event loop thread, where a blocking shutdown traps.
        group.shutdownGracefully { _ in }
    }

    public var identity: LocalIdentity { state.withLockedValue { $0.identity } }
    var discoveryChannel: Channel? { state.withLockedValue { $0.udp } }
    public var tcpPort: Int { state.withLockedValue { $0.tcpPort } }

    public func rename(_ name: String) {
        state.withLockedValue { $0.identity.deviceName = DeviceIdentifier.filterName(name) }
    }

    /// IP addresses that get our identity directly, for networks that drop broadcasts.
    public var customHosts: [String] {
        get { state.withLockedValue { $0.customHosts } }
        set { state.withLockedValue { $0.customHosts = newValue } }
    }

    // MARK: Lifecycle

    /// Binds the TCP server and UDP discovery socket. `announce: false` skips the first broadcast.
    public func start(announce: Bool = true) async throws {
        state.withLockedValue { $0.stopping = false }
        let tcp = try await bindTCPServer()
        let udp = try await bindDiscoverySocket()
        state.withLockedValue {
            $0.tcp = tcp
            $0.udp = udp
            $0.tcpPort = tcp.localAddress?.port ?? Self.udpPort
        }
        watch(udp, isDiscovery: true)
        watch(tcp, isDiscovery: false)
        lanLog.info("Listening on TCP \(self.tcpPort) and UDP \(Self.udpPort)")
        if announce { broadcast() }
    }

    private func bindDiscoverySocket() async throws -> Channel {
        try await DatagramBootstrap(group: group)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelOption(.socketOption(.so_reuseport), value: 1)
            .channelOption(.socketOption(.so_broadcast), value: 1)
            .channelInitializer { [unowned self] channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(DiscoveryHandler(provider: self))
                }
            }
            .bind(host: "0.0.0.0", port: Self.udpPort)
            .get()
    }

    /// A network drop can make the OS fail a socket read (EADDRNOTAVAIL, ENETDOWN), and NIO
    /// closes the channel. Reopen it, retrying until the network is back, then announce again.
    private func watch(_ channel: Channel, isDiscovery: Bool) {
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self, !self.state.withLockedValue({ $0.stopping }) else { return }
            trace("\(isDiscovery ? "UDP discovery socket" : "TCP server") closed; reopening")
            Task { await self.reopen(isDiscovery: isDiscovery) }
        }
    }

    private func reopen(isDiscovery: Bool) async {
        for attempt in 1... {
            try? await Task.sleep(for: .seconds(min(30, attempt * 2)))
            if state.withLockedValue({ $0.stopping }) { return }
            do {
                let channel = isDiscovery ? try await bindDiscoverySocket() : try await bindTCPServer(preferring: tcpPort)
                state.withLockedValue { state in
                    if isDiscovery {
                        state.udp = channel
                    } else {
                        state.tcp = channel
                        state.tcpPort = channel.localAddress?.port ?? state.tcpPort
                    }
                }
                watch(channel, isDiscovery: isDiscovery)
                trace("\(isDiscovery ? "UDP discovery socket" : "TCP server") reopened")
                broadcast()
                return
            } catch {
                trace("reopen attempt \(attempt) failed: \(error)")
            }
        }
    }

    /// When no packet of an announcement can be sent, macOS is probably blocking this process's
    /// sockets: right after an update replaced the app, before macOS registered the new binary for
    /// local network access, or before the person answered the local network prompt. Sockets made
    /// later get the current permission, so make new ones (at most every 30 seconds); watch()
    /// reopens both and announces again.
    private func refreshSocketsAfterFailedAnnouncement() {
        let channels: [Channel] = state.withLockedValue { state in
            guard !state.stopping, Date().timeIntervalSince(state.lastSocketRefresh) > 30 else { return [] }
            state.lastSocketRefresh = Date()
            return [state.udp, state.tcp].compactMap { $0 }
        }
        guard !channels.isEmpty else { return }
        trace("couldn't announce on any network; making new sockets")
        for channel in channels { channel.close(promise: nil) }
    }

    public func stop() {
        let (udp, tcp, links) = state.withLockedValue { state in
            state.stopping = true
            defer { state.udp = nil; state.tcp = nil }
            return (state.udp, state.tcp, Array(state.links.values))
        }
        udp?.close(promise: nil)
        tcp?.close(promise: nil)
        links.forEach { $0.close() }
    }

    private func bindTCPServer(preferring preferred: Int? = nil) async throws -> Channel {
        var lastError: Error = LinkError.noFreePort
        let ports = (preferred.map { [$0] } ?? []) + Self.tcpPorts.filter { $0 != preferred }
        for port in ports {
            do {
                return try await ServerBootstrap(group: group)
                    .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                    .childChannelOption(.socketOption(.so_keepalive), value: 1)
                    .childChannelOption(.tcpOption(.tcp_nodelay), value: 1)
                    .childChannelInitializer { [unowned self] channel in
                        channel.eventLoop.makeCompletedFuture {
                            Self.tuneKeepAlive(channel)
                            try channel.pipeline.syncOperations.addHandlers(
                                ByteToMessageHandler(LineDecoder()),
                                LinkHandshakeHandler(provider: self, direction: .incoming)
                            )
                        }
                    }
                    .bind(host: "0.0.0.0", port: port)
                    .get()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: Discovery

    /// Announces this Mac on every network it's on, plus any custom hosts.
    public func broadcast() {
        let (udp, identity, port, hosts) = state.withLockedValue { ($0.udp, $0.identity, $0.tcpPort, $0.customHosts) }
        guard let udp, let data = try? identity.discoveryPacket(tcpPort: port).serialized() else { return }

        // 255.255.255.255 plus each interface's subnet broadcast. Phones may hear this twice, and
        // Android reconnects on every announcement it hears, so callers only announce when a phone
        // is missing or the network really changed, never while everything is connected.
        var targets: [String] = ["255.255.255.255"]
        for device in (try? System.enumerateDevices()) ?? [] {
            guard let broadcast = device.broadcastAddress, case .v4 = broadcast, let ip = broadcast.ipAddress else { continue }
            if !targets.contains(ip) { targets.append(ip) }
        }
        targets += hosts
        let failures = NIOLockedValueBox(0)
        for ip in targets {
            guard let address = try? SocketAddress(ipAddress: ip, port: Self.udpPort) else { continue }
            let envelope = AddressedEnvelope(remoteAddress: address, data: udp.allocator.buffer(data: data))
            udp.writeAndFlush(envelope).whenFailure { [weak self] error in
                trace("UDP send to \(ip) failed: \(error)")
                let everyOneFailed = failures.withLockedValue { count in
                    count += 1
                    return count == targets.count
                }
                if everyOneFailed { self?.refreshSocketsAfterFailedAnnouncement() }
            }
        }
        trace("broadcast identity to \(targets.joined(separator: ", ")) (tcpPort \(port))")
    }

    /// Sends our identity to one address (also used to ask a device to connect back to us).
    public func announce(to host: String) {
        let (udp, identity, port) = state.withLockedValue { ($0.udp, $0.identity, $0.tcpPort) }
        guard let udp, let data = try? identity.discoveryPacket(tcpPort: port).serialized(),
              let address = try? SocketAddress(ipAddress: host, port: Self.udpPort)
        else { return }
        udp.writeAndFlush(AddressedEnvelope(remoteAddress: address, data: udp.allocator.buffer(data: data)), promise: nil)
    }

    func discoveryReceived(_ data: Data, from address: SocketAddress) {
        guard let packet = try? NetworkPacket(data: data), packet.type == PacketType.identity,
              let deviceId = packet["deviceId"]?.string, DeviceIdentifier.isValid(deviceId),
              deviceId != identity.deviceId,
              let rawHost = address.ipAddress
        else { return }
        let host = LinkHandshakeHandler.unmapped(rawHost)
        guard !host.hasPrefix("127."), host != "::1" else { return } // like the desktop app
        trace("UDP identity from \(packet["deviceName"]?.string ?? "?") at \(host), protocol \(packet["protocolVersion"]?.int ?? 0), tcpPort \(packet["tcpPort"]?.int ?? 0)")
        let version = Int(packet["protocolVersion"]?.int ?? 0)
        let port = Int(packet["tcpPort"]?.int ?? Int64(Self.udpPort))
        guard version >= LocalIdentity.protocolVersion, Self.tcpPorts.contains(port) else { return }
        if let trusted = trust.device(deviceId), trusted.protocolVersion > version { return }

        // At most one attempt per device every half second, like the desktop app.
        let now = Date()
        let throttled = state.withLockedValue { state -> Bool in
            if let last = state.lastAttempt[deviceId], now.timeIntervalSince(last) < 0.5 { return true }
            state.lastAttempt[deviceId] = now
            return false
        }
        guard !throttled else { return }
        connect(host: host, port: port, deviceId: deviceId, protocolVersion: version)
    }

    func connect(host: String, port: Int, deviceId: String, protocolVersion: Int) {
        trace("connecting to \(host):\(port)")
        ClientBootstrap(group: group)
            .connectTimeout(.seconds(5))
            .channelOption(.socketOption(.so_keepalive), value: 1)
            .channelOption(.tcpOption(.tcp_nodelay), value: 1)
            .channelInitializer { [unowned self] channel in
                channel.eventLoop.makeCompletedFuture {
                    Self.tuneKeepAlive(channel)
                    try channel.pipeline.syncOperations.addHandlers(
                        ByteToMessageHandler(LineDecoder()),
                        LinkHandshakeHandler(provider: self, direction: .outgoing(deviceId: deviceId, protocolVersion: protocolVersion))
                    )
                }
            }
            .connect(host: host, port: port)
            .whenFailure { [weak self] error in
                lanLog.notice("Could not connect to \(host, privacy: .public):\(port): \(String(describing: error), privacy: .public); asking it to connect back")
                self?.announce(to: host)
            }
    }

    /// Notice a silently vanished phone within about a minute instead of two hours.
    private static func tuneKeepAlive(_ channel: Channel) {
        guard let options = channel.syncOptions else { return }
        try? options.setOption(.tcpOption(NIOBSDSocket.Option(rawValue: TCP_KEEPALIVE)), value: 30)
        try? options.setOption(.tcpOption(NIOBSDSocket.Option(rawValue: TCP_KEEPINTVL)), value: 10)
        try? options.setOption(.tcpOption(NIOBSDSocket.Option(rawValue: TCP_KEEPCNT)), value: 3)
    }

    // MARK: Links

    /// During TLS: a paired device must present exactly the certificate we pinned.
    func acceptsCertificate(_ certificate: NIOSSLCertificate?, for deviceId: String?) -> Bool {
        guard let certificate, let deviceId, let der = try? certificate.toDERBytes() else { return false }
        if let trusted = trust.device(deviceId) { return Array(trusted.certificateDER) == der }
        return true
    }

    func linkEstablished(_ link: DeviceLink) {
        let replaced = state.withLockedValue { state -> (DeviceLink?, rejected: Bool) in
            if let existing = state.links[link.deviceId], existing.isOpen {
                // A second connection may only take over if it's the same device (same certificate).
                guard existing.certificateDER == link.certificateDER else { return (nil, true) }
                state.links[link.deviceId] = link
                return (existing, false)
            }
            state.links[link.deviceId] = link
            return (nil, false)
        }
        if replaced.rejected {
            lanLog.notice("Ignoring a second connection from \(link.info.name, privacy: .public) with a different certificate")
            link.close()
            return
        }
        lanLog.info("Connected to \(link.info.name, privacy: .public) (\(link.remoteHost ?? "?", privacy: .public))")
        trace("linked \(link.info.name) at \(link.remoteHost ?? "?")\(replaced.0 == nil ? "" : " (replacing an older connection)")")
        onLink?(link)
        replaced.0?.close()
    }

    func linkClosed(_ link: DeviceLink) {
        state.withLockedValue { state in
            if state.links[link.deviceId] === link { state.links[link.deviceId] = nil }
        }
    }

    public func link(for deviceId: String) -> DeviceLink? {
        state.withLockedValue { $0.links[deviceId] }
    }
}

/// UDP 1716: identity broadcasts from other devices.
final class DiscoveryHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private unowned let provider: LanLinkProvider

    init(provider: LanLinkProvider) {
        self.provider = provider
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        guard envelope.data.readableBytes < 64 * 1024 else { return }
        provider.discoveryReceived(Data(buffer: envelope.data), from: envelope.remoteAddress)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Sends fail while macOS waits for Local Network permission; keep the socket open.
        lanLog.debug("UDP error: \(String(describing: error), privacy: .public)")
    }
}

/// TLS settings shared by every connection. Certificates are self-signed, so the chain is not
/// verified; trust comes from pinning the certificate at pairing time (`acceptsCertificate`).
struct TLSContexts {
    let server: NIOSSLContext
    let client: NIOSSLContext

    init(identity: LocalIdentity) throws {
        var server = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(identity.certificate)],
            privateKey: .privateKey(identity.privateKey)
        )
        server.certificateVerification = .noHostnameVerification // require a client certificate
        server.trustRoots = .certificates([])
        server.minimumTLSVersion = .tlsv12

        var client = TLSConfiguration.makeClientConfiguration()
        client.certificateChain = [.certificate(identity.certificate)]
        client.privateKey = .privateKey(identity.privateKey)
        client.certificateVerification = .noHostnameVerification
        client.trustRoots = .certificates([])
        client.minimumTLSVersion = .tlsv12

        self.server = try NIOSSLContext(configuration: server)
        self.client = try NIOSSLContext(configuration: client)
    }
}
