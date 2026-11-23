import Foundation
import NIOConcurrencyHelpers

/// A paired device: its pinned certificate and what we last knew about it.
public struct TrustedDevice: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var type: String
    public var certificateDER: Data
    public var protocolVersion: Int
    public var pairedAt: Date

    public init(id: String, name: String, type: String, certificateDER: Data, protocolVersion: Int, pairedAt: Date = .now) {
        self.id = id
        self.name = name
        self.type = type
        self.certificateDER = certificateDER
        self.protocolVersion = protocolVersion
        self.pairedAt = pairedAt
    }
}

/// Paired devices, saved as JSON. Read from network threads during TLS handshakes (to pin
/// certificates), written from the main actor when pairing changes, hence the lock.
public final class TrustStore: @unchecked Sendable {
    private let url: URL
    private let state: NIOLockedValueBox<[String: TrustedDevice]>

    public init(directory: URL) {
        url = directory.appendingPathComponent("trusted-devices.json")
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([TrustedDevice].self, from: $0) } ?? []
        state = NIOLockedValueBox(Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))
    }

    public var devices: [TrustedDevice] {
        state.withLockedValue { Array($0.values) }.sorted { $0.pairedAt < $1.pairedAt }
    }

    public func device(_ id: String) -> TrustedDevice? { state.withLockedValue { $0[id] } }
    public func isTrusted(_ id: String) -> Bool { device(id) != nil }

    public func trust(_ device: TrustedDevice) {
        state.withLockedValue { $0[device.id] = device }
        save()
    }

    public func update(_ id: String, name: String, type: String, protocolVersion: Int) {
        let changed = state.withLockedValue { devices -> Bool in
            guard var device = devices[id], device.name != name || device.type != type || device.protocolVersion != protocolVersion
            else { return false }
            device.name = name
            device.type = type
            device.protocolVersion = protocolVersion
            devices[id] = device
            return true
        }
        if changed { save() }
    }

    public func forget(_ id: String) {
        state.withLockedValue { _ = $0.removeValue(forKey: id) }
        save()
    }

    private func save() {
        let devices = self.devices
        guard let data = try? JSONEncoder().encode(devices) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
