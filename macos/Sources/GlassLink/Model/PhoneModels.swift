import AppKit
import Foundation
import KDEConnectKit

enum PairState: Equatable {
    case notPaired
    /// We asked; waiting for the phone. `timestamp` feeds the pairing code.
    case requested(timestamp: Int64)
    /// The phone asked; waiting for the user.
    case requestedByPeer(timestamp: Int64)
    case paired

    var isPending: Bool {
        switch self {
        case .requested, .requestedByPeer: true
        default: false
        }
    }
}

struct BatteryState: Equatable {
    var level: Int
    var isCharging: Bool
    var isLow: Bool
}

struct SignalState: Identifiable, Equatable {
    var id: String
    var networkType: String
    /// 0–4 bars.
    var strength: Int
}

struct PhoneNotification: Identifiable, Equatable {
    var id: String
    var appName: String
    var title: String
    var text: String
    var time: Date
    var isClearable: Bool
    var isSilent: Bool
    var replyId: String?
    var actions: [String]
    var iconHash: String?

    init?(packet: NetworkPacket) {
        guard let id = packet["id"]?.string else { return nil }
        self.id = id
        appName = packet["appName"]?.string ?? "Android"
        title = packet["title"]?.string ?? ""
        text = packet["text"]?.string ?? packet["ticker"]?.string ?? ""
        let millis = packet["time"]?.int ?? Int64(Date().timeIntervalSince1970 * 1000)
        time = Date(timeIntervalSince1970: Double(millis) / 1000)
        isClearable = packet["isClearable"]?.bool ?? true
        isSilent = packet["silent"]?.bool ?? false
        replyId = packet["requestReplyId"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        actions = packet["actions"]?.stringArray ?? []
        iconHash = packet["payloadHash"]?.string
    }
}

struct SMSMessage: Identifiable, Hashable {
    var id: Int64
    var threadId: Int64
    var body: String
    var date: Date
    var isOutgoing: Bool
    var addresses: [String]
    var isRead: Bool
    var subscriptionId: Int64
    /// Shown until the phone reports the message it actually sent.
    var isPending = false

    /// Android `Telephony.Sms.TYPE`: 1 inbox, 2 sent, 4 outbox, 5 failed, 6 queued.
    init?(json: JSONValue) {
        guard let threadId = json["thread_id"]?.int else { return nil }
        id = json["_id"]?.int ?? Int64.random(in: 1...Int64.max)
        self.threadId = threadId
        body = json["body"]?.string ?? ""
        date = Date(timeIntervalSince1970: Double(json["date"]?.int ?? 0) / 1000)
        let type = json["type"]?.int ?? 1
        isOutgoing = type != 1
        addresses = json["addresses"]?.array?.compactMap { $0["address"]?.string } ?? []
        isRead = (json["read"]?.int ?? 1) != 0
        subscriptionId = json["sub_id"]?.int ?? -1
    }

    init(pendingBody body: String, threadId: Int64, addresses: [String]) {
        id = -Int64.random(in: 1...Int64.max)
        self.threadId = threadId
        self.body = body
        date = .now
        isOutgoing = true
        self.addresses = addresses
        isRead = true
        subscriptionId = -1
        isPending = true
    }
}

struct Conversation: Identifiable, Hashable {
    var id: Int64 { threadId }
    var threadId: Int64
    var addresses: [String]
    var latest: SMSMessage
}

struct CallState: Equatable {
    enum Kind: String { case ringing, talking, missedCall }
    var kind: Kind
    var number: String
    var name: String
    var photo: NSImage?

    static func == (a: CallState, b: CallState) -> Bool {
        a.kind == b.kind && a.number == b.number && a.name == b.name
    }
}

@MainActor
@Observable
final class Transfer: Identifiable {
    enum Direction { case incoming, outgoing }
    enum Status: Equatable { case active, finished, failed(String) }

    let id = UUID()
    let direction: Direction
    let filename: String
    var total: Int64
    var done: Int64 = 0
    var status = Status.active
    var fileURL: URL?
    let started = Date()

    init(direction: Direction, filename: String, total: Int64, fileURL: URL? = nil) {
        self.direction = direction
        self.filename = filename
        self.total = total
        self.fileURL = fileURL
    }

    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
}

/// Phone numbers compared by their last 9 digits, so "+1 (555) 010-2030" matches "5550102030".
enum PhoneNumber {
    static func key(_ number: String) -> String {
        String(number.filter(\.isNumber).suffix(9))
    }
}

/// Just enough vCard parsing for names and numbers.
enum VCard {
    struct Contact {
        var name: String
        var numbers: [String]
    }

    static func parse(_ text: String) -> Contact? {
        var name: String?
        var structured: String?
        var numbers: [String] = []
        // Unfold continuation lines (RFC 6350 §3.2) and quoted-printable soft breaks ("=" at the
        // end of a line), which Android's vCard 2.1 export uses for long non-ASCII names.
        let unfolded = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "=\n", with: "")
            .replacingOccurrences(of: "\n ", with: "")
        for line in unfolded.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].uppercased()
            var value = String(line[line.index(after: colon)...])
            if key.contains("QUOTED-PRINTABLE") { value = decodeQuotedPrintable(value) }
            if key == "FN" || key.hasPrefix("FN;") {
                name = value
            } else if key == "N" || key.hasPrefix("N;") {
                let parts = value.split(separator: ";", omittingEmptySubsequences: false)
                structured = [parts.count > 1 ? parts[1] : "", parts.first ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            } else if key.hasPrefix("TEL") {
                numbers.append(value)
            }
        }
        guard let display = name ?? structured, !display.isEmpty else { return nil }
        return Contact(name: display, numbers: numbers)
    }

    /// `=E0=A6=B0` → the UTF-8 bytes they spell.
    static func decodeQuotedPrintable(_ text: String) -> String {
        var bytes: [UInt8] = []
        var chars = Array(text.utf8)[...]
        while let byte = chars.popFirst() {
            if byte == UInt8(ascii: "="), chars.count >= 2,
               let value = UInt8(String(decoding: chars.prefix(2), as: UTF8.self), radix: 16)
            {
                bytes.append(value)
                chars = chars.dropFirst(2)
            } else {
                bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
