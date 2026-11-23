import AppKit
import SwiftUI
import Foundation
import KDEConnectKit
import os

let appLog = Logger(subsystem: "io.github.atikulmunna.glasslink", category: "app")

/// `GLASSLINK_TRACE=1` also prints app events to stderr.
func appTrace(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["GLASSLINK_TRACE"] != nil else { return }
    FileHandle.standardError.write(Data(("[app] " + message() + "\n").utf8))
}

/// One phone: its connection, pairing state, and everything it has told us.
@MainActor
@Observable
final class PhoneDevice: Identifiable {
    let id: String
    var name: String
    var type: String
    private(set) var link: DeviceLink?
    var pairState: PairState
    var lastSeen: Date?

    var battery: BatteryState?
    var signals: [SignalState] = []
    var notifications: [PhoneNotification] = []
    var conversations: [Conversation] = []
    var threads: [Int64: [SMSMessage]] = [:]
    var contacts: [String: String] = [:] // PhoneNumber.key → name
    var call: CallState?
    var transfers: [Transfer] = []
    var icons: [String: NSImage] = [:] // notification icon hash → image
    /// Set while the phone is ringing this Mac (its "find my device" feature).
    var isBeingFound = false
    /// The phone's lock-screen wallpaper (GlassLink for Android), cached between launches.
    var wallpaper: NSImage?
    var wallpaperColors: [NSColor] = []
    var screenshotStatus = ScreenshotSyncStatus.off {
        didSet { if screenshotStatus != oldValue { appTrace("screenshot sync: \(screenshotStatus)") } }
    }

    /// The pretend phone of `GLASSLINK_DEMO=1`: looks connected, sends nothing.
    @ObservationIgnored var isDemo = false
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var pairTimeout: Task<Void, Never>?
    @ObservationIgnored private var iconDownloads: Set<String> = []
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncScheduledEarly = false
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private var screenshotWatcher: PhoneScreenshotWatcher?
    @ObservationIgnored var fileServerFailures = 0
    /// Features waiting for a permission on the phone ("Finish setting up"), as the phone names them.
    var setupMissing: [String] = []
    /// Features running without an optional permission (for example calls without contact names).
    var setupLimited: [String] = []
    /// Phone screen mirroring (GlassLink for Android).
    @ObservationIgnored lazy var mirror = MirrorController(device: self)

    init(trusted: TrustedDevice, app: AppModel) {
        id = trusted.id
        name = trusted.name
        type = trusted.type
        pairState = .paired
        self.app = app
        wallpaper = NSImage(contentsOf: wallpaperFile)
    }

    private var wallpaperFile: URL {
        (app?.supportDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent("wallpaper-\(id).jpg")
    }

    init(link: DeviceLink, app: AppModel) {
        id = link.deviceId
        name = link.info.name
        type = link.info.type
        pairState = app.trust.isTrusted(link.deviceId) ? .paired : .notPaired
        self.app = app
    }

    var isConnected: Bool { link?.isOpen ?? isDemo }
    var isPaired: Bool { pairState == .paired }
    var isReady: Bool { isConnected && isPaired }
    var unreadNotifications: Int { notifications.count }
    /// The phone's address, for display (screenshot mode shows a made-up one).
    var remoteHost: String? { DemoData.isScreenshotMode ? DemoData.sampleAddress : link?.remoteHost }

    var symbolName: String {
        switch type {
        case "tablet": "ipad.landscape"
        case "tv": "tv"
        case "desktop": "desktopcomputer"
        case "laptop": "laptopcomputer"
        default: "smartphone"
        }
    }

    /// The code both screens show while pairing.
    var pairingCode: String? {
        guard let link, let identity = app?.provider?.identity else { return nil }
        switch pairState {
        case .requested(let timestamp), .requestedByPeer(let timestamp):
            return PairingCode.make(localSPKI: identity.publicKeySPKI, remoteSPKI: link.publicKeySPKI, timestamp: timestamp)
        default:
            return nil
        }
    }

    func send(_ packet: NetworkPacket) {
        guard let link, link.info.accepts(packet.type) || packet.type == PacketType.pair else { return }
        link.send(packet)
    }

    // MARK: Connection

    func attach(_ link: DeviceLink) {
        let previous = self.link
        self.link = link
        name = link.info.name
        type = link.info.type
        lastSeen = .now
        if isPaired {
            app?.trust.update(id, name: name, type: type, protocolVersion: link.info.protocolVersion)
        }

        Task { [weak self] in
            for await packet in link.packets {
                self?.receive(packet)
            }
            self?.detach(link)
        }
        // When a live connection is merely swapped for a new socket (the phone reconnects every
        // time it hears a broadcast), the phone keeps its session, so there's nothing to re-ask.
        // A first connection, or one that replaces a sync still in flight, syncs.
        let swappedLiveSocket = previous != nil && lastSync != nil && syncTask == nil
        if isPaired, !swappedLiveSocket { didConnect() }
    }

    private func detach(_ link: DeviceLink) {
        guard self.link === link else { return }
        self.link = nil
        lastSync = nil
        mirror.linkLost()
        fileServerFailures = 0
        screenshotWatcher?.stop()
        screenshotWatcher = nil
        screenshotStatus = .off
        lastSeen = .now
        call = nil
        if pairState.isPending { pairState = .notPaired }
        app?.deviceDisconnected(self)
    }

    /// Schedule the initial sync for a freshly connected, paired phone.
    ///
    /// The Android app starts reading a new connection before its plugins have loaded, and drops
    /// anything that arrives in between ("no plugin can handle it"). So wait until the phone sends
    /// its first packet (its plugins announce themselves, e.g. the battery level) plus a moment,
    /// or three seconds, whichever comes first.
    private func didConnect() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.performSync()
        }
    }

    private func phoneLooksReady() {
        guard syncTask != nil, !syncScheduledEarly else { return }
        syncScheduledEarly = true
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.performSync()
        }
    }

    /// Ask again right away, e.g. after the user granted a permission on the phone.
    func resync() {
        fileServerFailures = 0
        if case .watching = screenshotStatus {} else { stopScreenshotSync() }
        performSync()
    }

    private func performSync() {
        syncTask = nil
        syncScheduledEarly = false
        guard isReady else { return }
        lastSync = .now
        if DemoData.isScreenshotMode {
            // Real phone, made-up notifications and messages: never ask for the real ones.
            DemoData.fillSampleContent(self)
            if link?.info.outgoingCapabilities.contains(PacketType.glasslinkWallpaper) == true {
                send(NetworkPacket(type: PacketType.glasslinkWallpaperRequest))
            }
            return
        }
        send(NetworkPacket(type: PacketType.notificationRequest, body: ["request": true]))
        requestSetupStatus()
        requestConversations()
        send(NetworkPacket(type: PacketType.contactsRequestAllUIDs))
        if link?.info.outgoingCapabilities.contains(PacketType.glasslinkWallpaper) == true {
            send(NetworkPacket(type: PacketType.glasslinkWallpaperRequest))
        }
        if Prefs.phoneScreenshots {
            if supportsScreenshotPush {
                screenshotStatus = .pushed
            } else if screenshotWatcher == nil {
                requestFileAccess()
            }
        }
        if Prefs.sendClipboard, let text = app?.clipboard.currentText {
            send(NetworkPacket(type: PacketType.clipboardConnect, body: [
                "content": .string(text),
                "timestamp": .int(app?.clipboard.lastChange ?? 0),
            ]))
        }
    }

    // MARK: Pairing

    func requestPairing() {
        guard isConnected, !isPaired else { return }
        if case .requestedByPeer = pairState { return acceptPairing() }
        let timestamp = Int64(Date().timeIntervalSince1970)
        pairState = .requested(timestamp: timestamp)
        send(NetworkPacket(type: PacketType.pair, body: ["pair": true, "timestamp": .int(timestamp)]))
        startPairTimeout()
    }

    func acceptPairing() {
        guard case .requestedByPeer = pairState else { return }
        send(NetworkPacket(type: PacketType.pair, body: ["pair": true]))
        pairingSucceeded()
    }

    func rejectPairing() {
        guard pairState.isPending else { return }
        pairTimeout?.cancel()
        send(NetworkPacket(type: PacketType.pair, body: ["pair": false]))
        pairState = .notPaired
    }

    func unpair() {
        send(NetworkPacket(type: PacketType.pair, body: ["pair": false]))
        becameUnpaired()
    }

    private func startPairTimeout() {
        pairTimeout?.cancel()
        pairTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.pairState.isPending else { return }
            self.send(NetworkPacket(type: PacketType.pair, body: ["pair": false]))
            self.pairState = .notPaired
        }
    }

    private func pairingSucceeded() {
        pairTimeout?.cancel()
        guard let link else { return }
        app?.trust.trust(TrustedDevice(id: id, name: name, type: type, certificateDER: Data(link.certificateDER),
                                       protocolVersion: link.info.protocolVersion))
        pairState = .paired
        app?.devicePaired(self)
        didConnect()
    }

    private func becameUnpaired() {
        pairTimeout?.cancel()
        app?.trust.forget(id)
        pairState = .notPaired
        notifications = []
        conversations = []
        threads = [:]
        contacts = [:]
        battery = nil
        signals = []
        app?.deviceUnpaired(self)
    }

    /// The desktop app's pairing state machine (kdeconnect-kde `PairingHandler`).
    private func receivePair(_ packet: NetworkPacket) {
        let wantsPair = packet["pair"]?.bool ?? false
        if wantsPair {
            switch pairState {
            case .requested:
                pairingSucceeded()
            case .requestedByPeer:
                break
            case .paired, .notPaired:
                // A request (as opposed to an accept) carries a timestamp. From a paired phone it
                // means the phone forgot us: start over.
                guard let timestamp = packet["timestamp"]?.int else { return }
                if isPaired { becameUnpaired() }
                guard abs(timestamp - Int64(Date().timeIntervalSince1970)) <= 1800 else {
                    appLog.notice("Ignoring pairing request from \(self.name, privacy: .public): clocks differ by more than 30 minutes")
                    return
                }
                pairState = .requestedByPeer(timestamp: timestamp)
                startPairTimeout()
                app?.pairingRequested(by: self)
            }
        } else {
            switch pairState {
            case .notPaired:
                break
            case .requested, .requestedByPeer:
                pairTimeout?.cancel()
                pairState = .notPaired
            case .paired:
                becameUnpaired()
            }
        }
    }

    // MARK: Incoming packets

    private func receive(_ packet: NetworkPacket) {
        lastSeen = .now
        if packet.type == PacketType.pair { return receivePair(packet) }
        guard isPaired else {
            // The phone thinks we're paired but we aren't; tell it, like the desktop app does.
            send(NetworkPacket(type: PacketType.pair, body: ["pair": false]))
            return
        }
        phoneLooksReady()
        if DemoData.isScreenshotMode, [PacketType.notification, PacketType.smsMessages, PacketType.telephony,
                                       PacketType.contactsResponseUIDs, PacketType.contactsResponseVCards,
                                       PacketType.clipboard, PacketType.clipboardConnect].contains(packet.type) {
            return // keep real content out of screenshots
        }
        switch packet.type {
        case PacketType.ping:
            app?.notifier.post(title: name, body: packet["message"]?.string ?? "Ping!", deviceId: id)
        case PacketType.battery:
            receiveBattery(packet)
        case PacketType.connectivityReport:
            receiveConnectivity(packet)
        case PacketType.clipboard, PacketType.clipboardConnect:
            receiveClipboard(packet)
        case PacketType.notification:
            receiveNotification(packet)
        case PacketType.share:
            receiveShare(packet)
        case PacketType.telephony:
            receiveTelephony(packet)
        case PacketType.smsMessages:
            receiveMessages(packet)
        case PacketType.contactsResponseUIDs:
            receiveContactIDs(packet)
        case PacketType.contactsResponseVCards:
            receiveVCards(packet)
        case PacketType.findMyPhone:
            app?.startFindingMac(for: self)
        case PacketType.sftp:
            receiveFileServer(packet)
        case PacketType.glasslinkScreenshot:
            receivePushedImage(packet, isScreenshot: true)
        case PacketType.glasslinkClipboardImage:
            receivePushedImage(packet, isScreenshot: false)
        case PacketType.glasslinkWallpaper:
            receiveWallpaper(packet)
        case PacketType.glasslinkMirror:
            mirror.receive(packet)
        case PacketType.glasslinkSetup:
            setupMissing = packet["missing"]?.array?.compactMap(\.string) ?? []
            setupLimited = packet["limited"]?.array?.compactMap(\.string) ?? []
            trace("\(name) setup: missing [\(setupMissing.joined(separator: ", "))], limited [\(setupLimited.joined(separator: ", "))]")
        case PacketType.glasslinkClipboardRequest:
            sendClipboard() // the phone tapped "Get Mac's clipboard"
        default:
            appLog.debug("Unhandled packet \(packet.type, privacy: .public)")
        }
    }

    private func receiveBattery(_ packet: NetworkPacket) {
        guard let level = packet["currentCharge"]?.int, level >= 0 else { return }
        let state = BatteryState(level: Int(level), isCharging: packet["isCharging"]?.bool ?? false,
                                 isLow: packet["thresholdEvent"]?.int == 1)
        if state.isLow, battery?.isLow != true, !state.isCharging {
            app?.notifier.post(title: "\(name) battery is low", body: "\(state.level)% remaining", deviceId: id)
        }
        battery = state
    }

    private func receiveConnectivity(_ packet: NetworkPacket) {
        guard let strengths = packet["signalStrengths"]?.object else { return }
        signals = strengths.keys.sorted().compactMap { key in
            guard let entry = strengths[key] else { return nil }
            return SignalState(id: key, networkType: entry["networkType"]?.string ?? "",
                               strength: Int(entry["signalStrength"]?.int ?? 0))
        }
    }

    private func receiveClipboard(_ packet: NetworkPacket) {
        guard Prefs.receiveClipboard, let content = packet["content"]?.string, !content.isEmpty else { return }
        // The "connect" variant carries a timestamp: only take it if it's newer than ours.
        if packet.type == PacketType.clipboardConnect, let stamp = packet["timestamp"]?.int,
           stamp == 0 || stamp < (app?.clipboard.lastChange ?? 0)
        {
            return
        }
        app?.clipboard.setFromPhone(content)
    }

    // MARK: Notifications

    private func receiveNotification(_ packet: NetworkPacket) {
        if packet["isCancel"]?.bool == true, let id = packet["id"]?.string {
            notifications.removeAll { $0.id == id }
            app?.notifier.removePhoneNotification(id: id, deviceId: self.id)
            return
        }
        guard let notification = PhoneNotification(packet: packet) else { return }
        let isNew = !notifications.contains { $0.id == notification.id }
        notifications.removeAll { $0.id == notification.id }
        notifications.insert(notification, at: 0)
        notifications.sort { $0.time > $1.time }

        if let hash = notification.iconHash, icons[hash] == nil, packet.hasPayload, !iconDownloads.contains(hash) {
            iconDownloads.insert(hash)
            Task {
                if let data = try? await link?.downloadPayload(of: packet), let image = NSImage(data: data) {
                    icons[hash] = image
                }
                iconDownloads.remove(hash)
                if isNew, !notification.isSilent { mirror(notification) }
            }
        } else if isNew, !notification.isSilent {
            mirror(notification)
        }
    }

    private func mirror(_ notification: PhoneNotification) {
        guard Prefs.mirrorNotifications else { return }
        app?.notifier.postPhoneNotification(notification, icon: notification.iconHash.flatMap { icons[$0] }, device: self)
    }

    func dismiss(_ notification: PhoneNotification) {
        notifications.removeAll { $0.id == notification.id }
        send(NetworkPacket(type: PacketType.notificationRequest, body: ["cancel": .string(notification.id)]))
        app?.notifier.removePhoneNotification(id: notification.id, deviceId: id)
    }

    func dismissAll() {
        for notification in notifications where notification.isClearable { dismiss(notification) }
    }

    func reply(to replyId: String, message: String) {
        send(NetworkPacket(type: PacketType.notificationReply, body: ["requestReplyId": .string(replyId), "message": .string(message)]))
    }

    func trigger(_ action: String, on notification: PhoneNotification) {
        send(NetworkPacket(type: PacketType.notificationAction, body: ["key": .string(notification.id), "action": .string(action)]))
    }

    // MARK: Calls

    private func receiveTelephony(_ packet: NetworkPacket) {
        let number = packet["phoneNumber"]?.string ?? ""
        let name = packet["contactName"]?.string ?? displayName(for: number)
        if packet["isCancel"]?.bool == true {
            call = nil
            app?.notifier.removeCallNotification(deviceId: id)
            return
        }
        guard let event = packet["event"]?.string, let kind = CallState.Kind(rawValue: event) else { return }
        var photo: NSImage?
        if let base64 = packet["phoneThumbnail"]?.string, let data = Data(base64Encoded: base64) { photo = NSImage(data: data) }
        switch kind {
        case .ringing, .talking:
            call = CallState(kind: kind, number: number, name: name, photo: photo)
            if kind == .ringing { app?.notifier.postIncomingCall(name: name, number: number, device: self) }
        case .missedCall:
            call = nil
            app?.notifier.removeCallNotification(deviceId: id)
            app?.notifier.post(title: "Missed call", body: name == number ? number : "\(name) · \(number)", deviceId: id)
        }
    }

    func muteRinger() {
        send(NetworkPacket(type: PacketType.telephonyMute))
    }

    // MARK: Messages

    func requestConversations() {
        send(NetworkPacket(type: PacketType.smsRequestConversations))
    }

    func requestThread(_ threadId: Int64, before: Date? = nil) {
        var body: [String: JSONValue] = ["threadID": .int(threadId), "numberToRequest": 60]
        if let before { body["rangeStartTimestamp"] = .int(Int64(before.timeIntervalSince1970 * 1000)) }
        send(NetworkPacket(type: PacketType.smsRequestConversation, body: body))
    }

    func sendMessage(_ text: String, in conversation: Conversation) {
        sendMessage(text, to: conversation.addresses, threadId: conversation.threadId)
    }

    func sendMessage(_ text: String, to addresses: [String], threadId: Int64? = nil) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !addresses.isEmpty else { return }
        send(NetworkPacket(type: PacketType.smsRequest, body: [
            "version": 2,
            "addresses": .array(addresses.map { .object(["address": .string($0)]) }),
            "messageBody": .string(body),
        ]))
        if let threadId {
            threads[threadId, default: []].append(SMSMessage(pendingBody: body, threadId: threadId, addresses: addresses))
        }
    }

    private func receiveMessages(_ packet: NetworkPacket) {
        guard let list = packet["messages"]?.array else { return }
        let messages = list.compactMap(SMSMessage.init(json:))
        var touched = Set<Int64>()
        for message in messages {
            var thread = threads[message.threadId, default: []]
            if let index = thread.firstIndex(where: { $0.id == message.id }) {
                thread[index] = message
            } else {
                // The phone's copy of something we just sent replaces the placeholder.
                if message.isOutgoing, let pending = thread.firstIndex(where: { $0.isPending && $0.body == message.body }) {
                    thread.remove(at: pending)
                }
                thread.append(message)
            }
            threads[message.threadId] = thread
            touched.insert(message.threadId)

            if let index = conversations.firstIndex(where: { $0.threadId == message.threadId }) {
                if message.date >= conversations[index].latest.date { conversations[index].latest = message }
            } else {
                conversations.append(Conversation(threadId: message.threadId, addresses: message.addresses, latest: message))
            }
        }
        for id in touched { threads[id]?.sort { $0.date < $1.date } }
        conversations.sort { $0.latest.date > $1.latest.date }
    }

    func displayName(for address: String) -> String {
        contacts[PhoneNumber.key(address)] ?? address
    }

    func title(for conversation: Conversation) -> String {
        conversation.addresses.map(displayName(for:)).joined(separator: ", ")
    }

    // MARK: Contacts

    private func receiveContactIDs(_ packet: NetworkPacket) {
        let ids = packet["uids"]?.stringArray ?? []
        guard !ids.isEmpty else { return }
        send(NetworkPacket(type: PacketType.contactsRequestVCards, body: ["uids": JSONValue(ids)]))
    }

    private func receiveVCards(_ packet: NetworkPacket) {
        for uid in packet["uids"]?.stringArray ?? [] {
            guard let card = packet[uid]?.string, let contact = VCard.parse(card) else { continue }
            for number in contact.numbers { contacts[PhoneNumber.key(number)] = contact.name }
        }
    }

    // MARK: GlassLink for Android extras

    /// The phone runs GlassLink's own Android app, which pushes screenshots by itself.
    var supportsScreenshotPush: Bool { link?.info.outgoingCapabilities.contains(PacketType.glasslinkScreenshot) ?? false }
    /// The phone can put images we send onto its clipboard.
    var supportsImageClipboard: Bool { link?.info.incomingCapabilities.contains(PacketType.glasslinkClipboardImage) ?? false }

    func sendClipboardImage(_ file: URL) {
        guard let link, supportsImageClipboard else { return }
        let packet = NetworkPacket(type: PacketType.glasslinkClipboardImage, body: ["mimeType": "image/png"])
        Task { try? await link.send(packet, payload: .file(file)) }
    }

    private func receiveWallpaper(_ packet: NetworkPacket) {
        wallpaperColors = (packet["colors"]?.stringArray ?? []).compactMap(NSColor.init(hex:))
        guard packet.hasPayload, let link else { return }
        let file = wallpaperFile
        let partial = file.appendingPathExtension("download")
        Task {
            do {
                try await link.downloadPayload(of: packet, to: partial)
                guard let image = NSImage(contentsOf: partial) else { return }
                _ = try? FileManager.default.replaceItemAt(file, withItemAt: partial)
                withAnimation(.glass) { wallpaper = image }
            } catch {
                try? FileManager.default.removeItem(at: partial)
                appTrace("wallpaper download failed: \(error)")
            }
        }
    }

    /// Asks the phone which features still need a permission; `show` also opens its setup screen.
    func requestSetupStatus(show: Bool = false) {
        guard isReady, link?.info.outgoingCapabilities.contains(PacketType.glasslinkSetup) == true else { return }
        send(NetworkPacket(type: PacketType.glasslinkSetupRequest, body: show ? ["show": true] : [:]))
    }

    /// The phone can share its screen (GlassLink for Android).
    var supportsMirroring: Bool { link?.info.outgoingCapabilities.contains(PacketType.glasslinkMirror) ?? false }

    var supportsClipboardRequest: Bool {
        link?.info.incomingCapabilities.contains(PacketType.glasslinkClipboardRequest) ?? false
    }

    /// Asks the phone for its clipboard; it arrives as a normal clipboard update.
    func requestPhoneClipboard() {
        send(NetworkPacket(type: PacketType.glasslinkClipboardRequest))
    }

    /// A screenshot (pushed when taken) or an image copied on the phone: onto the Mac clipboard,
    /// with the floating thumbnail.
    private func receivePushedImage(_ packet: NetworkPacket, isScreenshot: Bool) {
        guard packet.hasPayload, let link else { return }
        if isScreenshot, !Prefs.phoneScreenshots { return }
        if !isScreenshot, !Prefs.syncImageClipboard { return }
        let name = packet["filename"]?.string ?? "Copied Image \(Int(Date().timeIntervalSince1970)).png"
        let destination = ScreenshotFiles.destination(for: name)
        Task {
            do {
                try? FileManager.default.removeItem(at: destination)
                try await link.downloadPayload(of: packet, to: destination)
                guard let image = NSImage(contentsOf: destination) else { return }
                app?.clipboard.setImageFromPhone(image, file: destination)
                ScreenshotToast.show(image: image, file: destination, source: self.name, copied: true)
            } catch {
                appTrace("image from phone failed: \(error)")
            }
        }
    }

    // MARK: Screenshots (phone file server)

    /// Asks the phone to start its file server; the reply carries an address and password.
    func requestFileAccess() {
        guard isReady, Prefs.phoneScreenshots else { return }
        screenshotStatus = .connecting
        send(NetworkPacket(type: PacketType.sftpRequest, body: ["startBrowsing": true]))
    }

    func stopScreenshotSync() {
        screenshotWatcher?.stop()
        screenshotWatcher = nil
        screenshotStatus = .off
    }

    private func receiveFileServer(_ packet: NetworkPacket) {
        guard Prefs.phoneScreenshots, let link, let app else { return }
        // Besides replies (an address or an error), the phone sends bare status updates.
        guard packet["port"] != nil || packet["errorMessage"] != nil else {
            if packet["serverRunning"]?.bool == false, screenshotWatcher != nil { screenshotStatus = .connecting }
            return
        }
        screenshotWatcher?.stop()
        let watcher = PhoneScreenshotWatcher(device: self)
        screenshotWatcher = watcher
        watcher.start(reply: packet, link: link, app: app)
    }

    // MARK: Find my phone / ping

    func ring() {
        send(NetworkPacket(type: PacketType.findMyPhone))
    }

    func ping() {
        send(NetworkPacket(type: PacketType.ping, body: ["message": .string("Hello from \(app?.localName ?? "your Mac")")]))
    }

    // MARK: Sharing

    enum ClipboardSendResult { case text, image, nothing }

    /// Sends the Mac clipboard: text as text, an image onto the phone's clipboard (GlassLink for
    /// Android) or as a file (KDE Connect).
    @discardableResult
    func sendClipboard() -> ClipboardSendResult {
        guard let clipboard = app?.clipboard else { return .nothing }
        if let text = clipboard.currentText {
            send(NetworkPacket(type: PacketType.clipboard, body: ["content": .string(text)]))
            return .text
        }
        if let image = clipboard.imageForSending() {
            if supportsImageClipboard { sendClipboardImage(image) } else { send(files: [image]) }
            return .image
        }
        return .nothing
    }

    func share(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), !trimmed.contains(" ") {
            send(NetworkPacket(type: PacketType.share, body: ["url": .string(trimmed)]))
        } else {
            send(NetworkPacket(type: PacketType.share, body: ["text": .string(trimmed)]))
        }
    }

    func send(files urls: [URL]) {
        let files = urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        guard let link, !files.isEmpty else { return }
        let sizes = files.map { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
        let totalSize = sizes.reduce(0, +)
        let jobs = zip(files, sizes).map { url, size in
            let transfer = Transfer(direction: .outgoing, filename: url.lastPathComponent, total: size, fileURL: url)
            transfers.insert(transfer, at: 0)
            return (url, transfer)
        }
        Task {
            for (url, transfer) in jobs {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
                let packet = NetworkPacket(type: PacketType.share, body: [
                    "filename": .string(url.lastPathComponent),
                    "lastModified": .int(Int64(modified.timeIntervalSince1970 * 1000)),
                    "numberOfFiles": .int(Int64(jobs.count)),
                    "totalPayloadSize": .int(totalSize),
                ])
                do {
                    try await link.send(packet, payload: .file(url)) { sent, total in
                        Task { @MainActor in
                            transfer.done = sent
                            transfer.total = total
                        }
                    }
                    transfer.done = transfer.total
                    transfer.status = .finished
                } catch {
                    transfer.status = .failed(String(describing: error))
                }
            }
        }
    }

    private func receiveShare(_ packet: NetworkPacket) {
        if let text = packet["text"]?.string {
            app?.clipboard.setFromPhone(text)
            app?.notifier.post(title: "Text from \(name)", body: "Copied to the clipboard: \(text.prefix(120))", deviceId: id)
        } else if let urlString = packet["url"]?.string, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else if let filename = packet["filename"]?.string, packet.hasPayload {
            receiveFile(named: filename, packet: packet)
        }
    }

    private func receiveFile(named filename: String, packet: NetworkPacket) {
        let safeName = (filename as NSString).lastPathComponent.replacingOccurrences(of: ":", with: "-")
        let destination = Self.uniqueURL(in: Prefs.downloadsFolder, name: safeName.isEmpty ? "File" : safeName)
        let partial = destination.appendingPathExtension("download")
        let transfer = Transfer(direction: .incoming, filename: destination.lastPathComponent, total: packet.payloadSize ?? 0)
        transfers.insert(transfer, at: 0)
        let shouldOpen = packet["open"]?.bool ?? false
        let modified = packet["lastModified"]?.int.map { Date(timeIntervalSince1970: Double($0) / 1000) }

        Task {
            do {
                try await link?.downloadPayload(of: packet, to: partial) { received, total in
                    Task { @MainActor in
                        transfer.done = received
                        if total > 0 { transfer.total = total }
                    }
                }
                try FileManager.default.moveItem(at: partial, to: destination)
                if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: destination.path) }
                transfer.fileURL = destination
                transfer.done = transfer.total
                transfer.status = .finished
                if shouldOpen { NSWorkspace.shared.open(destination) }
                app?.notifier.postFileReceived(destination, from: self)
            } catch {
                try? FileManager.default.removeItem(at: partial)
                transfer.status = .failed(String(describing: error))
            }
        }
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

extension NSColor {
    /// "#RRGGBB"
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
