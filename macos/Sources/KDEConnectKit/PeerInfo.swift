import Foundation
import os

let lanLog = Logger(subsystem: "io.github.atikulmunna.glasslink", category: "lan")

/// `GLASSLINK_TRACE=1` also prints protocol events to stderr (handy under `swift test`).
let traceEnabled = ProcessInfo.processInfo.environment["GLASSLINK_TRACE"] != nil

public func trace(_ message: @autoclosure () -> String) {
    guard traceEnabled else { return }
    FileHandle.standardError.write(Data(("[kdeconnect] " + message() + "\n").utf8))
}

/// What a peer said about itself in its (encrypted) identity packet.
public struct PeerInfo: Sendable, Hashable {
    public var deviceId: String
    public var name: String
    public var type: String
    public var protocolVersion: Int
    public var incomingCapabilities: Set<String>
    public var outgoingCapabilities: Set<String>

    init?(identity packet: NetworkPacket) {
        guard packet.type == PacketType.identity,
              let id = packet["deviceId"]?.string, DeviceIdentifier.isValid(id),
              let rawName = packet["deviceName"]?.string
        else { return nil }
        let name = DeviceIdentifier.filterName(rawName)
        deviceId = id
        self.name = name
        type = packet["deviceType"]?.string ?? "phone"
        protocolVersion = Int(packet["protocolVersion"]?.int ?? 0)
        incomingCapabilities = Set(packet["incomingCapabilities"]?.stringArray ?? [])
        outgoingCapabilities = Set(packet["outgoingCapabilities"]?.stringArray ?? [])
    }

    /// Whether the peer will act on packets of this type (an empty list means "everything",
    /// which is what peers that predate capabilities send).
    public func accepts(_ type: String) -> Bool { incomingCapabilities.isEmpty || incomingCapabilities.contains(type) }
    public func sends(_ type: String) -> Bool { outgoingCapabilities.isEmpty || outgoingCapabilities.contains(type) }
}

public enum LinkError: Error, CustomStringConvertible {
    case packetTooLarge
    case invalidIdentity(String)
    case handshakeTimeout
    case certificateMismatch
    case notConnected
    case noFreePort
    case payloadTruncated(received: Int64, expected: Int64)
    case transferTimedOut

    public var description: String {
        switch self {
        case .packetTooLarge: "packet too large"
        case .invalidIdentity(let why): "invalid identity: \(why)"
        case .handshakeTimeout: "handshake timed out"
        case .certificateMismatch: "certificate does not match the paired device"
        case .notConnected: "device is not connected"
        case .noFreePort: "no free port for the transfer"
        case .payloadTruncated(let received, let expected): "transfer ended early (\(received) of \(expected) bytes)"
        case .transferTimedOut: "the other device did not start the transfer"
        }
    }
}
