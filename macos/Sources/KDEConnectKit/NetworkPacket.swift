import Foundation

/// One KDE Connect packet: a JSON object on a single line, terminated by `\n`.
///
/// ```json
/// {"id": 1700000000000, "type": "kdeconnect.ping", "body": {}}
/// ```
///
/// A packet can announce a payload (a file, a notification icon) that travels on a separate TLS
/// connection: `payloadSize` gives its length and `payloadTransferInfo.port` the port to fetch it from.
public struct NetworkPacket: Sendable, CustomStringConvertible {
    public var id: Int64
    public var type: String
    public var body: [String: JSONValue]
    public var payloadSize: Int64?
    public var payloadTransferInfo: [String: JSONValue]?

    public init(type: String, body: [String: JSONValue] = [:]) {
        self.id = Int64(Date().timeIntervalSince1970 * 1000)
        self.type = type
        self.body = body
    }

    public subscript(key: String) -> JSONValue? {
        get { body[key] }
        set { body[key] = newValue }
    }

    public var hasPayload: Bool { payloadTransferInfo?["port"]?.int != nil }
    public var payloadPort: Int? { payloadTransferInfo?["port"]?.int.map(Int.init) }

    public var description: String {
        let keys = body.keys.sorted().joined(separator: ",")
        return "\(type) {\(keys)}" + (payloadSize.map { " +\($0)B" } ?? "")
    }

    // MARK: Wire format

    public func serialized() throws -> Data {
        var object: [String: Any] = [
            "id": id,
            "type": type,
            "body": body.mapValues(\.foundationValue),
        ]
        if let payloadSize { object["payloadSize"] = payloadSize }
        if let payloadTransferInfo { object["payloadTransferInfo"] = payloadTransferInfo.mapValues(\.foundationValue) }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public init(data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw PacketError.notAnObject
        }
        guard let type = object["type"] as? String, !type.isEmpty else { throw PacketError.missingType }
        self.type = type
        self.id = JSONValue(foundation: object["id"] ?? 0).int ?? 0
        self.body = (object["body"] as? [String: Any])?.mapValues(JSONValue.init(foundation:)) ?? [:]
        if let size = object["payloadSize"] { self.payloadSize = JSONValue(foundation: size).int }
        if let info = object["payloadTransferInfo"] as? [String: Any] {
            self.payloadTransferInfo = info.mapValues(JSONValue.init(foundation:))
        }
    }
}

public enum PacketError: Error, CustomStringConvertible {
    case notAnObject
    case missingType

    public var description: String {
        switch self {
        case .notAnObject: "packet is not a JSON object"
        case .missingType: "packet has no type"
        }
    }
}

/// Packet types this app speaks. Names match the KDE Connect plugins on Android and the desktop.
public enum PacketType {
    public static let identity = "kdeconnect.identity"
    public static let pair = "kdeconnect.pair"

    public static let ping = "kdeconnect.ping"
    public static let battery = "kdeconnect.battery"
    public static let connectivityReport = "kdeconnect.connectivity_report"
    public static let clipboard = "kdeconnect.clipboard"
    public static let clipboardConnect = "kdeconnect.clipboard.connect"
    public static let findMyPhone = "kdeconnect.findmyphone.request"

    public static let notification = "kdeconnect.notification"
    public static let notificationRequest = "kdeconnect.notification.request"
    public static let notificationReply = "kdeconnect.notification.reply"
    public static let notificationAction = "kdeconnect.notification.action"

    public static let share = "kdeconnect.share.request"
    public static let shareUpdate = "kdeconnect.share.request.update"

    public static let telephony = "kdeconnect.telephony"
    public static let telephonyMute = "kdeconnect.telephony.request_mute"

    public static let smsMessages = "kdeconnect.sms.messages"
    public static let smsRequest = "kdeconnect.sms.request"
    public static let smsRequestConversations = "kdeconnect.sms.request_conversations"
    public static let smsRequestConversation = "kdeconnect.sms.request_conversation"

    public static let contactsRequestAllUIDs = "kdeconnect.contacts.request_all_uids_timestamps"
    public static let contactsRequestVCards = "kdeconnect.contacts.request_vcards_by_uid"
    public static let contactsResponseUIDs = "kdeconnect.contacts.response_uids_timestamps"
    public static let contactsResponseVCards = "kdeconnect.contacts.response_vcards"

    /// The phone's file server (Android "Filesystem expose" plugin).
    public static let sftp = "kdeconnect.sftp"
    public static let sftpRequest = "kdeconnect.sftp.request"

    /// GlassLink's own Android app (a KDE Connect fork). Official KDE apps ignore these.
    /// A screenshot, pushed the moment it's saved (payload: the image).
    public static let glasslinkScreenshot = "glasslink.screenshot"
    /// An image copied on either device (payload: the image; body: `mimeType`).
    public static let glasslinkClipboardImage = "glasslink.clipboard.image"
    /// Ask the phone to send its current clipboard (it briefly raises an invisible activity).
    public static let glasslinkClipboardRequest = "glasslink.clipboard.request"
    /// The phone's lock-screen wallpaper (payload: JPEG; body: `colors` as "#RRGGBB").
    public static let glasslinkWallpaper = "glasslink.wallpaper"
    public static let glasslinkWallpaperRequest = "glasslink.wallpaper.request"
    /// Screen mirroring: the Mac asks (`start`), the phone answers with its state and stream port,
    /// and the Mac sends touches (`action`: tap, longpress, swipe, back, home, recents).
    public static let glasslinkMirror = "glasslink.mirror"
    public static let glasslinkMirrorRequest = "glasslink.mirror.request"
    public static let glasslinkMirrorInput = "glasslink.mirror.input"
    /// Which features are still waiting for a permission on the phone (`missing`, `limited`); the
    /// Mac asks with `glasslink.setup.request` (`show`: true opens the phone's setup screen).
    public static let glasslinkSetup = "glasslink.setup"
    public static let glasslinkSetupRequest = "glasslink.setup.request"
    /// Answer, decline or end the phone's call (`action`); the call itself stays on the phone.
    public static let glasslinkCallRequest = "glasslink.call.request"
    /// From the phone: open the Phone Screen window (which then asks the phone to share).
    public static let glasslinkMirrorOffer = "glasslink.mirror.offer"
    /// From the phone: lock this Mac (sleep the display).
    public static let glasslinkMacLock = "glasslink.mac.lock"
}
