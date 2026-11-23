import Crypto
import _CryptoExtras
import Foundation

/// The phone's file server (SFTP) uses the same key pair as its KDE Connect certificate, so the
/// paired certificate tells us exactly which SSH host key to expect. This turns that key into an
/// OpenSSH `known_hosts` entry.
public enum SSHPublicKey {
    /// `"ssh-rsa AAAA…"` or `"ecdsa-sha2-nistp256 AAAA…"`, from a DER SubjectPublicKeyInfo.
    public static func openSSH(fromSPKI spki: [UInt8]) -> String? {
        if let rsa = try? _RSA.Signing.PublicKey(unsafeDERRepresentation: spki),
           let primitives = try? rsa.getKeyPrimitives()
        {
            var blob = Data()
            blob.appendSSHString(Data("ssh-rsa".utf8))
            blob.appendSSHMPInt(primitives.publicExponent)
            blob.appendSSHMPInt(primitives.modulus)
            return "ssh-rsa " + blob.base64EncodedString()
        }
        if let ec = try? P256.Signing.PublicKey(derRepresentation: spki) {
            var blob = Data()
            blob.appendSSHString(Data("ecdsa-sha2-nistp256".utf8))
            blob.appendSSHString(Data("nistp256".utf8))
            blob.appendSSHString(ec.x963Representation)
            return "ecdsa-sha2-nistp256 " + blob.base64EncodedString()
        }
        return nil
    }
}

extension Data {
    mutating func appendSSHString(_ bytes: Data) {
        var length = UInt32(bytes.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { append(contentsOf: $0) }
        append(bytes)
    }

    /// RFC 4251 mpint: big-endian, no leading zeros, plus a zero byte if the top bit is set.
    mutating func appendSSHMPInt(_ magnitude: Data) {
        var bytes = Data(magnitude.drop(while: { $0 == 0 }))
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        appendSSHString(bytes)
    }
}
