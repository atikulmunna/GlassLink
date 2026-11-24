// Signs release checksums so GlassLink for Mac only installs updates you published.
//
//     swift tools/release-signing.swift keygen        create the key (once), print the public key
//     swift tools/release-signing.swift sign FILE     write FILE.sig (Ed25519, base64)
//     swift tools/release-signing.swift public        print the public key again
//
// The private key lives outside the repository, in ~/.glasslink/update-signing.key (or the file
// named by GLASSLINK_UPDATE_KEY), like the Android release key. Keep a backup: without it, Macs
// won't accept new updates. The public key is built into the app (macos/.../Updater.swift).

import CryptoKit
import Foundation

let keyPath = ProcessInfo.processInfo.environment["GLASSLINK_UPDATE_KEY"]
    ?? (NSHomeDirectory() as NSString).appendingPathComponent(".glasslink/update-signing.key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("No update signing key at \(keyPath). Create one with: swift tools/release-signing.swift keygen") }
    return key
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    guard !FileManager.default.fileExists(atPath: keyPath) else { fail("\(keyPath) already exists; not replacing it.") }
    let key = Curve25519.Signing.PrivateKey()
    let dir = (keyPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    FileManager.default.createFile(atPath: keyPath, contents: key.rawRepresentation.base64EncodedData(), attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let file = args.dropFirst().first, let data = FileManager.default.contents(atPath: file) else { fail("Usage: sign FILE") }
    let signature = try loadKey().signature(for: data)
    try signature.base64EncodedString().write(toFile: file + ".sig", atomically: true, encoding: .utf8)
    print("Signed \(file)")
default:
    fail("Usage: swift tools/release-signing.swift keygen | public | sign FILE")
}
