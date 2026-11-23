import Foundation
import KDEConnectKit

/// `GLASSLINK_DEMO=1` adds a pretend phone with sample data, for working on the UI without a
/// phone nearby. Nothing about it is saved or sent anywhere.
///
/// `GLASSLINK_SCREENSHOT=1` uses the real, connected phone (name, battery, signal, wallpaper) but
/// shows the sample notifications and messages instead of real ones, for README screenshots.
/// Real notifications, messages, contacts and calls are not requested or shown in that mode.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["GLASSLINK_DEMO"] != nil }
    static var isScreenshotMode: Bool { ProcessInfo.processInfo.environment["GLASSLINK_SCREENSHOT"] != nil }
    /// In screenshot mode the Mac calls itself this, and shows this address for the phone.
    static let sampleMacName = "MacBook Pro"
    static let sampleAddress = "192.168.1.42"

    /// Demo or screenshot mode: sample content, and `GLASSLINK_SECTION` picks the first screen.
    static var showsSampleContent: Bool { isEnabled || isScreenshotMode }

    @MainActor
    static func makeDevice(app: AppModel) -> PhoneDevice {
        let device = PhoneDevice(trusted: TrustedDevice(id: "demo_device_0000000000000000000000", name: "Pixel 9 Pro",
                                                        type: "phone", certificateDER: Data(), protocolVersion: 8),
                                 app: app)
        device.isDemo = true
        device.battery = BatteryState(level: 78, isCharging: true, isLow: false)
        device.signals = [SignalState(id: "1", networkType: "5G", strength: 3)]
        fillSampleContent(device)

        let received = Transfer(direction: .incoming, filename: "IMG_2041.HEIC", total: 3_400_000)
        received.done = received.total
        received.status = .finished
        let sending = Transfer(direction: .outgoing, filename: "Quarterly Report.pdf", total: 8_200_000)
        sending.done = 5_100_000
        device.transfers = [sending, received]
        return device
    }

    /// Made-up notifications, conversations and contact names.
    @MainActor
    static func fillSampleContent(_ device: PhoneDevice) {
        let now = Date()
        func note(_ id: String, _ app: String, _ title: String, _ text: String, minutesAgo: Double, reply: Bool = false, actions: [String] = []) -> PhoneNotification {
            var packet = NetworkPacket(type: PacketType.notification, body: [
                "id": .string(id), "appName": .string(app), "title": .string(title), "text": .string(text),
                "time": .int(Int64(now.addingTimeInterval(-minutesAgo * 60).timeIntervalSince1970 * 1000)),
                "isClearable": true, "actions": JSONValue(actions),
            ])
            if reply { packet["requestReplyId"] = .string("reply-\(id)") }
            return PhoneNotification(packet: packet)!
        }
        device.notifications = [
            note("1", "WhatsApp", "Maya", "Are we still on for dinner at 8? I booked the table 🍜", minutesAgo: 2, reply: true, actions: ["Mark as read"]),
            note("2", "Gmail", "Your boarding pass", "Flight LH 403 · Gate B22 · Boarding 17:40", minutesAgo: 14, actions: ["Archive", "Reply"]),
            note("3", "Calendar", "Design review", "In 30 minutes · Studio 3", minutesAgo: 31),
            note("4", "Slack", "#mobile-team", "Ana: the release build is green ✅", minutesAgo: 58, reply: true),
            note("5", "Spotify", "Now playing", "Glass Animals — Heat Waves", minutesAgo: 75),
        ]

        func sms(_ id: Int64, thread: Int64, _ address: String, _ body: String, minutesAgo: Double, outgoing: Bool, read: Bool = true) -> SMSMessage {
            SMSMessage(json: [
                "_id": .int(id), "thread_id": .int(thread), "body": .string(body),
                "date": .int(Int64(now.addingTimeInterval(-minutesAgo * 60).timeIntervalSince1970 * 1000)),
                "type": .int(outgoing ? 2 : 1), "read": .int(read ? 1 : 0),
                "addresses": .array([.object(["address": .string(address)])]),
            ])!
        }
        let maya = [
            sms(1, thread: 1, "+15550102030", "Hey! Landing around 6", minutesAgo: 190, outgoing: false),
            sms(2, thread: 1, "+15550102030", "Perfect, I'll pick you up", minutesAgo: 185, outgoing: true),
            sms(3, thread: 1, "+15550102030", "You're the best 🙌", minutesAgo: 184, outgoing: false),
            sms(4, thread: 1, "+15550102030", "Are we still on for dinner at 8?", minutesAgo: 2, outgoing: false, read: false),
        ]
        let bank = [sms(5, thread: 2, "72975", "Your verification code is 482913. It expires in 10 minutes.", minutesAgo: 40, outgoing: false)]
        let leo = [
            sms(6, thread: 3, "+15550199001", "Did you send the photos?", minutesAgo: 1500, outgoing: false),
            sms(7, thread: 3, "+15550199001", "Sending them from my Mac now", minutesAgo: 1490, outgoing: true),
        ]
        device.threads = [1: maya, 2: bank, 3: leo]
        device.conversations = [maya, bank, leo].map { Conversation(threadId: $0[0].threadId, addresses: $0[0].addresses, latest: $0.last!) }
        device.contacts = [PhoneNumber.key("+15550102030"): "Maya Chen", PhoneNumber.key("+15550199001"): "Leo Park"]
    }
}
