import AppKit
import KDEConnectKit
import UserNotifications

/// Mirrors phone events into Notification Center, with inline reply and quick actions.
@MainActor
final class MacNotifier: NSObject, UNUserNotificationCenterDelegate {
    private enum Category {
        static let reply = "phone.reply"
        static let plain = "phone.plain"
        static let pair = "pair.request"
        static let call = "call.incoming"
        static let callControl = "call.incoming.control"
        static let file = "file.received"
    }

    private enum Action {
        static let reply = "reply"
        static let dismiss = "dismiss"
        static let accept = "accept"
        static let decline = "decline"
        static let mute = "mute"
        static let answer = "answer"
        static let declineCall = "declineCall"
        static let reveal = "reveal"
    }

    private weak var app: AppModel?
    /// UserNotifications needs a real app bundle; under `swift run` there is none.
    private let available = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    private var center: UNUserNotificationCenter? { available ? UNUserNotificationCenter.current() : nil }

    func setUp(app: AppModel) {
        self.app = app
        guard let center else { return }
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: Action.reply, title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let dismiss = UNNotificationAction(identifier: Action.dismiss, title: "Dismiss on Phone")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.reply, actions: [reply, dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.plain, actions: [dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.pair, actions: [
                UNNotificationAction(identifier: Action.accept, title: "Pair", options: [.foreground]),
                UNNotificationAction(identifier: Action.decline, title: "Decline", options: [.destructive]),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.call, actions: [
                UNNotificationAction(identifier: Action.mute, title: "Silence Ringer"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.callControl, actions: [
                UNNotificationAction(identifier: Action.answer, title: "Answer on Phone"),
                UNNotificationAction(identifier: Action.declineCall, title: "Decline", options: [.destructive]),
                UNNotificationAction(identifier: Action.mute, title: "Silence Ringer"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.file, actions: [
                UNNotificationAction(identifier: Action.reveal, title: "Show in Finder", options: [.foreground]),
            ], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { @MainActor in self.refreshPermission() }
        }
    }

    /// Reads whether banners are allowed (the user may have declined, or never answered, the prompt).
    func refreshPermission() {
        guard let center else { return }
        center.getNotificationSettings { settings in
            let permission: AppModel.NotificationPermission
            switch settings.authorizationStatus {
            case .notDetermined: permission = .notAsked
            case .denied: permission = .off
            default: permission = settings.alertSetting == .disabled ? .off : .allowed
            }
            trace("Mac notifications: \(permission)")
            Task { @MainActor in self.app?.notificationPermission = permission }
        }
    }

    /// Asks again if macOS never got an answer; otherwise opens GlassLink in System Settings › Notifications.
    func fixPermission() {
        if app?.notificationPermission == .notAsked, let center {
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                Task { @MainActor in self.refreshPermission() }
            }
            return
        }
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Posting

    func post(title: String, body: String, deviceId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["device": deviceId]
        add(content, id: UUID().uuidString)
    }

    func postPhoneNotification(_ notification: PhoneNotification, icon: NSImage?, device: PhoneDevice) {
        let content = UNMutableNotificationContent()
        content.title = notification.title.isEmpty ? notification.appName : notification.title
        content.subtitle = notification.title.isEmpty ? "" : notification.appName
        content.body = notification.text
        content.sound = .default
        content.threadIdentifier = "\(device.id)/\(notification.appName)"
        content.categoryIdentifier = notification.replyId != nil ? Category.reply : Category.plain
        content.userInfo = ["device": device.id, "notification": notification.id, "replyId": notification.replyId ?? ""]
        if let icon, let attachment = Self.attachment(for: icon, key: notification.iconHash ?? notification.id) {
            content.attachments = [attachment]
        }
        add(content, id: Self.notificationKey(device.id, notification.id))
    }

    func removePhoneNotification(id: String, deviceId: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.notificationKey(deviceId, id)])
    }

    func postPairingRequest(from device: PhoneDevice) {
        let content = UNMutableNotificationContent()
        content.title = "\(device.name) wants to pair"
        content.body = device.pairingCode.map { "Check that your phone shows \($0)." } ?? "Open GlassLink to respond."
        content.sound = .default
        content.categoryIdentifier = Category.pair
        content.userInfo = ["device": device.id]
        add(content, id: "pair/\(device.id)")
    }

    func postIncomingCall(name: String, number: String, device: PhoneDevice) {
        let content = UNMutableNotificationContent()
        content.title = "Incoming call"
        content.body = name == number || number.isEmpty ? name : "\(name) · \(number)"
        content.sound = .default
        content.categoryIdentifier = device.supportsCallControl ? Category.callControl : Category.call
        content.userInfo = ["device": device.id]
        add(content, id: "call/\(device.id)")
    }

    func removeCallNotification(deviceId: String) {
        center?.removeDeliveredNotifications(withIdentifiers: ["call/\(deviceId)"])
    }

    func postFileReceived(_ url: URL, from device: PhoneDevice) {
        let content = UNMutableNotificationContent()
        content.title = "Received from \(device.name)"
        content.body = url.lastPathComponent
        content.categoryIdentifier = Category.file
        content.userInfo = ["device": device.id, "file": url.path]
        add(content, id: UUID().uuidString)
    }

    private func add(_ content: UNMutableNotificationContent, id: String) {
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { trace("notification not shown: \(error)") }
        }
    }

    private static func notificationKey(_ deviceId: String, _ id: String) -> String { "n/\(deviceId)/\(id)" }

    /// Notification attachments must be files; write the app icon to a temporary PNG.
    private static func attachment(for image: NSImage, key: String) -> UNNotificationAttachment? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let safe = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glasslink-\(String(safe.prefix(60))).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: url)
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void)
    {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        let deviceId = info["device"] as? String
        let notificationId = info["notification"] as? String
        let replyId = info["replyId"] as? String
        let file = info["file"] as? String
        Task { @MainActor in
            self.handle(action: action, deviceId: deviceId, notificationId: notificationId, replyId: replyId, text: typed, file: file)
            completionHandler()
        }
    }

    private func handle(action: String, deviceId: String?, notificationId: String?, replyId: String?, text: String?, file: String?) {
        guard let app, let deviceId, let device = app.devices[deviceId] else { return }
        switch action {
        case Action.reply:
            if let replyId, !replyId.isEmpty, let text, !text.isEmpty { device.reply(to: replyId, message: text) }
        case Action.dismiss:
            if let notificationId, let notification = device.notifications.first(where: { $0.id == notificationId }) {
                device.dismiss(notification)
            }
        case Action.accept:
            device.acceptPairing()
        case Action.decline:
            device.rejectPairing()
        case Action.mute:
            device.muteRinger()
        case Action.answer:
            device.answerCall()
        case Action.declineCall:
            device.declineCall()
        case Action.reveal:
            if let file { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }
        default:
            // Clicking the banner opens the app on that phone.
            app.selectedDeviceId = device.isPaired ? device.id : app.selectedDeviceId
            NSApp.activate()
            if let file { NSWorkspace.shared.open(URL(fileURLWithPath: file)) }
        }
    }
}
