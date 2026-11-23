import Crypto
import Foundation
import NIOSSL
import X509

/// This Mac as a KDE Connect device: a stable device ID and the self-signed certificate that
/// proves it. Peers pin the certificate when they pair, so it must never change for a given ID.
///
/// Like the KDE Connect desktop app, the certificate uses an EC P-256 key and has the device ID
/// as its common name (peers check that the two match), organisation "KDE", unit "KDE Connect".
public struct LocalIdentity: Sendable {
    public static let protocolVersion = 8

    public let deviceId: String
    public var deviceName: String
    public var deviceType: String
    public let certificate: NIOSSLCertificate
    public let privateKey: NIOSSLPrivateKey
    public let certificateDER: [UInt8]
    public let publicKeySPKI: [UInt8]

    /// Loads the identity saved in `directory`, creating it on first launch.
    public static func loadOrCreate(in directory: URL, deviceName: String, deviceType: String) throws -> LocalIdentity {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let idURL = directory.appendingPathComponent("device-id")
        let certURL = directory.appendingPathComponent("certificate.pem")
        let keyURL = directory.appendingPathComponent("private-key.pem")

        if let id = try? String(contentsOf: idURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           DeviceIdentifier.isValid(id),
           let certPEM = try? Data(contentsOf: certURL), let keyPEM = try? Data(contentsOf: keyURL),
           let identity = try? LocalIdentity(deviceId: id, certificatePEM: Array(certPEM), keyPEM: Array(keyPEM),
                                             deviceName: deviceName, deviceType: deviceType)
        {
            return identity
        }

        // First launch (or unreadable files): new ID, new key, new certificate.
        let id = DeviceIdentifier.generate()
        let (certPEM, keyPEM) = try makeSelfSignedCertificate(commonName: id)
        try Data(id.utf8).write(to: idURL, options: .atomic)
        try Data(certPEM.utf8).write(to: certURL, options: .atomic)
        try Data(keyPEM.utf8).write(to: keyURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return try LocalIdentity(deviceId: id, certificatePEM: Array(certPEM.utf8), keyPEM: Array(keyPEM.utf8),
                                 deviceName: deviceName, deviceType: deviceType)
    }

    init(deviceId: String, certificatePEM: [UInt8], keyPEM: [UInt8], deviceName: String, deviceType: String) throws {
        let certificate = try NIOSSLCertificate(bytes: certificatePEM, format: .pem)
        self.deviceId = deviceId
        self.deviceName = DeviceIdentifier.filterName(deviceName)
        self.deviceType = deviceType
        self.certificate = certificate
        self.privateKey = try NIOSSLPrivateKey(bytes: keyPEM, format: .pem)
        self.certificateDER = try certificate.toDERBytes()
        self.publicKeySPKI = try certificate.extractPublicKey().toSPKIBytes()
        guard CertificateInfo.commonName(ofDER: certificateDER) == deviceId else { throw IdentityError.mismatchedCertificate }
    }

    static func makeSelfSignedCertificate(commonName: String) throws -> (certificatePEM: String, keyPEM: String) {
        let key = P256.Signing.PrivateKey()
        let signingKey = Certificate.PrivateKey(key)
        let name = try DistinguishedName {
            OrganizationName("KDE")
            OrganizationalUnitName("KDE Connect")
            CommonName(commonName)
        }
        let year: TimeInterval = 365 * 24 * 60 * 60
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: signingKey.publicKey,
            notValidBefore: now - year,
            notValidAfter: now + 10 * year,
            issuer: name,
            subject: name,
            extensions: Certificate.Extensions(),
            issuerPrivateKey: signingKey
        )
        return (try certificate.serializeAsPEM().pemString, key.pemRepresentation)
    }

    // MARK: Identity packets (protocol version 8)

    /// Broadcast over UDP so phones on the network find us. Kept small on purpose.
    public func discoveryPacket(tcpPort: Int) -> NetworkPacket {
        NetworkPacket(type: PacketType.identity, body: [
            "deviceId": .string(deviceId),
            "deviceName": .string(deviceName),
            "protocolVersion": .int(Int64(Self.protocolVersion)),
            "tcpPort": .int(Int64(tcpPort)),
        ])
    }

    /// Sent in plain text right after we open a TCP connection to a device that announced itself.
    public func connectionPacket(targetDeviceId: String, targetProtocolVersion: Int) -> NetworkPacket {
        NetworkPacket(type: PacketType.identity, body: [
            "deviceId": .string(deviceId),
            "deviceName": .string(deviceName),
            "protocolVersion": .int(Int64(Self.protocolVersion)),
            "targetDeviceId": .string(targetDeviceId),
            "targetProtocolVersion": .int(Int64(targetProtocolVersion)),
        ])
    }

    /// The full identity, sent only once the connection is encrypted.
    public func identityPacket(capabilities: Capabilities) -> NetworkPacket {
        NetworkPacket(type: PacketType.identity, body: [
            "deviceId": .string(deviceId),
            "deviceName": .string(deviceName),
            "deviceType": .string(deviceType),
            "protocolVersion": .int(Int64(Self.protocolVersion)),
            "incomingCapabilities": JSONValue(capabilities.incoming.sorted()),
            "outgoingCapabilities": JSONValue(capabilities.outgoing.sorted()),
        ])
    }
}

public enum IdentityError: Error {
    case mismatchedCertificate
}

/// The packet types a device accepts and sends. Phones only load the plugins whose packet types
/// overlap with ours, so this list decides which features the phone turns on for this Mac.
public struct Capabilities: Sendable, Hashable {
    public var incoming: Set<String>
    public var outgoing: Set<String>

    public init(incoming: Set<String>, outgoing: Set<String>) {
        self.incoming = incoming
        self.outgoing = outgoing
    }
}

public enum DeviceIdentifier {
    /// A UUID with underscores, the format the desktop app uses (`^[a-zA-Z0-9_-]{32,38}$`).
    public static func generate() -> String {
        UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    public static func isValid(_ id: String) -> Bool {
        (32...38).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// Device names are limited to 32 characters without `"',;:.!?()[]<>`, as on the desktop.
    public static func filterName(_ name: String) -> String {
        let banned = Set("\"',;:.!?()[]<>")
        let filtered = String(name.filter { !banned.contains($0) }.prefix(32))
        return filtered.isEmpty ? "Mac" : filtered
    }
}

public enum CertificateInfo {
    /// The subject common name of a DER certificate, if it has one.
    public static func commonName(ofDER der: [UInt8]) -> String? {
        guard let certificate = try? Certificate(derEncoded: der) else { return nil }
        for rdn in certificate.subject {
            for attribute in rdn where attribute.type == .RDNAttributeType.commonName {
                if let value = String(attribute.value) { return value }
            }
        }
        return nil
    }

    /// SHA-256 of the DER certificate, as colon-separated hex (shown in device details).
    public static func fingerprint(ofDER der: [UInt8]) -> String {
        SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// The 8-character code both devices show while pairing, so the user can check they match.
///
/// SHA-256 over the two public keys (larger first, compared bytewise) followed by the pairing
/// request's timestamp in decimal; the first 8 hex digits, uppercase. Same as `PairingHandler`
/// in kdeconnect-kde and `SslHelper` on Android.
public enum PairingCode {
    public static func make(localSPKI: [UInt8], remoteSPKI: [UInt8], timestamp: Int64) -> String {
        var first = localSPKI
        var second = remoteSPKI
        if first.lexicographicallyPrecedes(second) { swap(&first, &second) }
        var hash = SHA256()
        hash.update(data: first)
        hash.update(data: second)
        hash.update(data: Array(String(timestamp).utf8))
        return hash.finalize().prefix(4).map { String(format: "%02X", $0) }.joined()
    }
}
