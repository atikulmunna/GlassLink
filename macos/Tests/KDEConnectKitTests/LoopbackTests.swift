import Foundation
import NIOConcurrencyHelpers
import NIOSSL
import Testing
@testable import KDEConnectKit

/// Two providers on this Mac talk to each other over loopback, playing "Mac" and "phone".
@Suite(.serialized)
struct LoopbackTests {
    static let capabilities = Capabilities(incoming: [PacketType.ping, PacketType.share], outgoing: [PacketType.ping, PacketType.share])

    static func makeProvider(_ name: String) throws -> (LanLinkProvider, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glasslink-test-\(UUID().uuidString)")
        let identity = try LocalIdentity.loadOrCreate(in: dir, deviceName: name, deviceType: "desktop")
        let provider = try LanLinkProvider(identity: identity, capabilities: capabilities, trust: TrustStore(directory: dir))
        return (provider, dir)
    }

    /// Waits for the first link each provider reports.
    final class LinkCatcher: @unchecked Sendable {
        let links = NIOLockedValueBox<[DeviceLink]>([])
        func attach(_ provider: LanLinkProvider) { provider.onLink = { link in self.links.withLockedValue { $0.append(link) } } }
        func first(timeout: Duration = .seconds(5)) async throws -> DeviceLink {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if let link = links.withLockedValue({ $0.first }) { return link }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw LinkError.handshakeTimeout
        }
    }

    @Test func identityPersistsAcrossLaunches() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glasslink-test-\(UUID().uuidString)")
        let first = try LocalIdentity.loadOrCreate(in: dir, deviceName: "Mac", deviceType: "laptop")
        let second = try LocalIdentity.loadOrCreate(in: dir, deviceName: "Mac", deviceType: "laptop")
        #expect(first.deviceId == second.deviceId)
        #expect(first.certificateDER == second.certificateDER)
        #expect(DeviceIdentifier.isValid(first.deviceId))
        #expect(CertificateInfo.commonName(ofDER: first.certificateDER) == first.deviceId)
    }

    @Test func packetRoundTrip() throws {
        var packet = NetworkPacket(type: PacketType.notification, body: ["id": "a/b", "isCancel": "true", "time": "1700000000000"])
        packet.payloadSize = 42
        packet.payloadTransferInfo = ["port": 1739]
        let data = try packet.serialized()
        #expect(data.last == UInt8(ascii: "\n"))
        let parsed = try NetworkPacket(data: data)
        #expect(parsed.type == PacketType.notification)
        #expect(parsed["isCancel"]?.bool == true)
        #expect(parsed["time"]?.int == 1_700_000_000_000)
        #expect(parsed["id"]?.string == "a/b")
        #expect(parsed.payloadPort == 1739)
        #expect(parsed.payloadSize == 42)
    }

    @Test func sshKeyMatchesOpenSSHFormat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glasslink-test-\(UUID().uuidString)")
        let identity = try LocalIdentity.loadOrCreate(in: dir, deviceName: "Mac", deviceType: "laptop")
        let line = try #require(SSHPublicKey.openSSH(fromSPKI: identity.publicKeySPKI))
        #expect(line.hasPrefix("ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY"))
        // ssh-keygen derives the same public key from our private key file.
        let keygen = Process()
        keygen.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        keygen.arguments = ["-y", "-f", dir.appendingPathComponent("private-key.pem").path]
        let out = Pipe()
        keygen.standardOutput = out
        try keygen.run()
        keygen.waitUntilExit()
        let derived = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(derived.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(line))
    }

    @Test func pairingCodeIsSymmetric() {
        let a: [UInt8] = [0x30, 0x59, 0x01]
        let b: [UInt8] = [0x30, 0x59, 0xFF]
        let one = PairingCode.make(localSPKI: a, remoteSPKI: b, timestamp: 1_700_000_000)
        let two = PairingCode.make(localSPKI: b, remoteSPKI: a, timestamp: 1_700_000_000)
        #expect(one == two)
        #expect(one.count == 8)
        #expect(one != PairingCode.make(localSPKI: a, remoteSPKI: b, timestamp: 1_700_000_001))
    }

    @Test func handshakePacketsAndPayload() async throws {
        let (mac, _) = try Self.makeProvider("Mac")
        let (phone, _) = try Self.makeProvider("Phone")
        let macLinks = LinkCatcher(), phoneLinks = LinkCatcher()
        macLinks.attach(mac)
        phoneLinks.attach(phone)
        try await mac.start(announce: false)
        try await phone.start(announce: false)
        defer { mac.stop(); phone.stop() }

        // The "phone" heard the Mac's broadcast and connects to its TCP port.
        phone.connect(host: "127.0.0.1", port: mac.tcpPort, deviceId: mac.identity.deviceId, protocolVersion: 8)
        let macSide = try await macLinks.first()
        let phoneSide = try await phoneLinks.first()

        #expect(macSide.info.deviceId == phone.identity.deviceId)
        #expect(macSide.info.name == "Phone")
        #expect(phoneSide.info.deviceId == mac.identity.deviceId)
        #expect(macSide.info.incomingCapabilities.contains(PacketType.ping))
        #expect(macSide.certificateDER == phone.identity.certificateDER)

        // Both sides compute the same pairing code.
        let codeOnMac = PairingCode.make(localSPKI: mac.identity.publicKeySPKI, remoteSPKI: macSide.publicKeySPKI, timestamp: 1234)
        let codeOnPhone = PairingCode.make(localSPKI: phone.identity.publicKeySPKI, remoteSPKI: phoneSide.publicKeySPKI, timestamp: 1234)
        #expect(codeOnMac == codeOnPhone)

        // A packet from the phone reaches the Mac.
        phoneSide.send(NetworkPacket(type: PacketType.ping, body: ["message": "hello"]))
        var iterator = macSide.packets.makeAsyncIterator()
        let ping = await iterator.next()
        #expect(ping?.type == PacketType.ping)
        #expect(ping?["message"]?.string == "hello")

        // A 3 MB payload from the Mac reaches the phone intact.
        let blob = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        async let sent: Void = macSide.send(NetworkPacket(type: PacketType.share, body: ["filename": "blob.bin"]), payload: .data(blob))
        var phoneIterator = phoneSide.packets.makeAsyncIterator()
        let share = try #require(await phoneIterator.next())
        #expect(share.payloadSize == Int64(blob.count))
        let received = try await phoneSide.downloadPayload(of: share)
        try await sent
        #expect(received == blob)
    }

    @Test func discoverySocketReopensAfterNetworkDrop() async throws {
        let (mac, _) = try Self.makeProvider("Mac")
        try await mac.start(announce: false)
        defer { mac.stop() }
        let first = try #require(mac.discoveryChannel)
        try await first.close() // what NIO does after EADDRNOTAVAIL when Wi-Fi drops
        let deadline = ContinuousClock.now + .seconds(6)
        while ContinuousClock.now < deadline {
            if let channel = mac.discoveryChannel, channel !== first, channel.isActive { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("discovery socket was not reopened")
    }

    @Test func pairedDeviceWithWrongCertificateIsRejected() async throws {
        let (mac, macDir) = try Self.makeProvider("Mac")
        let (phone, _) = try Self.makeProvider("Phone")
        // The Mac believes it is paired with this phone ID, but pinned some other certificate.
        let (otherPEM, _) = try LocalIdentity.makeSelfSignedCertificate(commonName: phone.identity.deviceId)
        let other = try derFromPEM(otherPEM)
        TrustStore(directory: macDir).trust(TrustedDevice(id: phone.identity.deviceId, name: "Phone", type: "phone",
                                                          certificateDER: Data(other), protocolVersion: 8))
        let reloaded = try LanLinkProvider(identity: mac.identity, capabilities: Self.capabilities, trust: TrustStore(directory: macDir))
        let macLinks = LinkCatcher()
        macLinks.attach(reloaded)
        try await reloaded.start(announce: false)
        try await phone.start(announce: false)
        defer { reloaded.stop(); phone.stop() }

        phone.connect(host: "127.0.0.1", port: reloaded.tcpPort, deviceId: reloaded.identity.deviceId, protocolVersion: 8)
        await #expect(throws: LinkError.self) { try await macLinks.first(timeout: .seconds(2)) }
    }
}

private func derFromPEM(_ pem: String) throws -> [UInt8] {
    try NIOSSLCertificate(bytes: Array(pem.utf8), format: .pem).toDERBytes()
}
