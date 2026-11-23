import AppKit
import Foundation
import IOKit.ps
import KDEConnectKit
import Network

enum Prefs {
    static let defaults = UserDefaults.standard

    static var receiveClipboard: Bool { defaults.object(forKey: "receiveClipboard") as? Bool ?? true }
    static var sendClipboard: Bool { defaults.object(forKey: "sendClipboard") as? Bool ?? true }
    static var mirrorNotifications: Bool { defaults.object(forKey: "mirrorNotifications") as? Bool ?? true }
    static var phoneScreenshots: Bool { defaults.object(forKey: "phoneScreenshots") as? Bool ?? true }
    static var sendMacScreenshots: Bool { defaults.object(forKey: "sendMacScreenshots") as? Bool ?? true }
    static var sendCopiedImages: Bool { defaults.object(forKey: "sendCopiedImages") as? Bool ?? false }
    static var syncImageClipboard: Bool { defaults.object(forKey: "syncImageClipboard") as? Bool ?? true }
    static var customHosts: [String] { (defaults.string(forKey: "customHosts") ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init) }

    static var downloadsFolder: URL {
        if let path = defaults.string(forKey: "downloadsFolder"), FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}

/// The app's root state: this Mac's identity, the network, and every known phone.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Status: Equatable {
        case starting
        case running
        case failed(String)
    }

    private(set) var status = Status.starting
    private(set) var devices: [String: PhoneDevice] = [:]
    var selectedDeviceId: String? {
        didSet { if !DemoData.isEnabled { UserDefaults.standard.set(selectedDeviceId, forKey: "selectedDevice") } }
    }
    /// A phone asking to pair, shown as a sheet.
    var pairingRequest: PhoneDevice?
    var localName: String

    @ObservationIgnored let trust: TrustStore
    @ObservationIgnored private(set) var provider: LanLinkProvider?
    @ObservationIgnored let clipboard = ClipboardSync()
    @ObservationIgnored let notifier = MacNotifier()
    @ObservationIgnored let supportDirectory: URL
    @ObservationIgnored var identityDirectory: URL { supportDirectory.appendingPathComponent("Identity", isDirectory: true) }
    @ObservationIgnored let macScreenshots = MacScreenshotWatcher()
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var findMacSound: NSSound?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDirectory = base.appendingPathComponent("GlassLink", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        trust = TrustStore(directory: supportDirectory)
        localName = DemoData.isScreenshotMode
            ? DemoData.sampleMacName // what the phone shows in screenshots; nothing is saved
            : UserDefaults.standard.string(forKey: "deviceName") ?? Host.current().localizedName ?? "Mac"
        selectedDeviceId = UserDefaults.standard.string(forKey: "selectedDevice")
        if DemoData.isEnabled {
            // Only the pretend phone: never show or touch real paired devices.
            let demo = DemoData.makeDevice(app: self)
            devices[demo.id] = demo
            selectedDeviceId = demo.id
        } else {
            for trusted in trust.devices {
                devices[trusted.id] = PhoneDevice(trusted: trusted, app: self)
            }
        }
    }

    // MARK: Lists

    var pairedDevices: [PhoneDevice] {
        devices.values.filter(\.isPaired).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Phones on the network running KDE Connect that aren't paired yet.
    var nearbyDevices: [PhoneDevice] {
        devices.values.filter { !$0.isPaired && $0.isConnected }.sorted { $0.name < $1.name }
    }

    /// The phone the window is showing.
    var current: PhoneDevice? {
        if let id = selectedDeviceId, let device = devices[id], device.isPaired { return device }
        return pairedDevices.first { $0.isConnected } ?? pairedDevices.first
    }

    var identity: LocalIdentity? { provider?.identity }

    // MARK: Lifecycle

    func start() async {
        guard provider == nil else { return }
        if DemoData.isEnabled {
            // Demo mode is for UI work: no network, no notifications, no clipboard.
            status = .running
            return
        }
        notifier.setUp(app: self)
        clipboard.onChange = { [weak self] text in self?.clipboardChanged(text) }
        clipboard.onImage = { [weak self] file in self?.copiedImage(file) }
        clipboard.start()
        macScreenshots.onScreenshot = { [weak self] file in
            guard Prefs.sendMacScreenshots else { return }
            self?.copiedImage(file)
        }
        macScreenshots.start()

        do {
            let identity = try LocalIdentity.loadOrCreate(
                in: identityDirectory,
                deviceName: localName, deviceType: Self.isLaptop ? "laptop" : "desktop")
            let provider = try LanLinkProvider(identity: identity, capabilities: Self.capabilities, trust: trust)
            provider.customHosts = Prefs.customHosts
            provider.onLink = { link in
                Task { @MainActor in AppModel.shared.attach(link) }
            }
            self.provider = provider
            try await provider.start()
            status = .running
        } catch {
            status = .failed(String(describing: error))
            return
        }

        watchNetwork()
        // Phones only see broadcasts sent while they're listening, so keep announcing
        // while a paired phone is away (cheap: one small UDP packet per network).
        heartbeat = Task { [weak self] in
            // Android reconnects every time it hears a broadcast, even when already connected, so
            // announce sparingly: 15 s, then doubling up to 5 min while a paired phone is missing.
            // A phone that comes back announces itself anyway.
            var delay = 15.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                let pairedMissing = self.pairedDevices.contains { !$0.isConnected }
                let nothingConnected = !self.devices.values.contains { $0.isConnected }
                if pairedMissing || nothingConnected {
                    self.provider?.broadcast()
                    delay = min(delay * 2, 300)
                } else {
                    delay = 15
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.rediscover() }
        }
    }

    func stop() {
        heartbeat?.cancel()
        provider?.stop()
    }

    /// Looks for phones again and re-asks connected ones for their notifications, messages and
    /// contacts (useful right after granting a permission on the phone).
    func refresh() {
        provider?.customHosts = Prefs.customHosts
        provider?.broadcast()
        for device in pairedDevices where device.isReady { device.resync() }
    }

    /// Announces this Mac again after a network change or wake, without re-syncing.
    func rediscover() {
        provider?.customHosts = Prefs.customHosts
        provider?.broadcast()
    }

    func rename(to name: String) {
        let filtered = DeviceIdentifier.filterName(name)
        localName = filtered
        UserDefaults.standard.set(filtered, forKey: "deviceName")
        provider?.rename(filtered)
        rediscover()
    }

    private func watchNetwork() {
        let monitor = NWPathMonitor()
        var isFirstUpdate = true
        monitor.pathUpdateHandler = { path in
            // The first update is the current network, not a change; we just broadcast at launch.
            defer { isFirstUpdate = false }
            guard path.status == .satisfied, !isFirstUpdate else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                AppModel.shared.rediscover()
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
    }

    // MARK: Devices

    private func attach(_ link: DeviceLink) {
        let device = devices[link.deviceId] ?? PhoneDevice(link: link, app: self)
        devices[link.deviceId] = device
        device.attach(link)
        if selectedDeviceId == nil, device.isPaired { selectedDeviceId = device.id }
    }

    func deviceDisconnected(_ device: PhoneDevice) {
        if pairingRequest === device { pairingRequest = nil }
        if !device.isPaired { devices[device.id] = nil }
    }

    func devicePaired(_ device: PhoneDevice) {
        if pairingRequest === device { pairingRequest = nil }
        selectedDeviceId = device.id
        notifier.post(title: "Paired with \(device.name)", body: "Notifications, messages and files will now appear here.", deviceId: device.id)
    }

    func deviceUnpaired(_ device: PhoneDevice) {
        if selectedDeviceId == device.id { selectedDeviceId = pairedDevices.first?.id }
        if !device.isConnected { devices[device.id] = nil }
    }

    func pairingRequested(by device: PhoneDevice) {
        pairingRequest = device
        notifier.postPairingRequest(from: device)
        NSApp.requestUserAttention(.informationalRequest)
    }

    // MARK: Clipboard

    private func clipboardChanged(_ text: String) {
        guard Prefs.sendClipboard else { return }
        for device in pairedDevices where device.isConnected {
            device.send(NetworkPacket(type: PacketType.clipboard, body: ["content": .string(text)]))
        }
    }

    /// An image (copied, or a new screenshot) goes onto the clipboard of phones running GlassLink
    /// for Android. Phones on stock KDE Connect can't take images on their clipboard; they get a
    /// file in Downloads only if the user opted in.
    private func copiedImage(_ file: URL) {
        for device in pairedDevices where device.isReady {
            if device.supportsImageClipboard {
                if Prefs.syncImageClipboard { device.sendClipboardImage(file) }
            } else if Prefs.sendCopiedImages {
                device.send(files: [file])
            }
        }
    }

    // MARK: Find my Mac

    func startFindingMac(for device: PhoneDevice) {
        device.isBeingFound = true
        let sound = NSSound(named: NSSound.Name("Funk")) ?? NSSound(named: NSSound.Name("Glass"))
        sound?.loops = true
        sound?.play()
        findMacSound = sound
        NSApp.activate()
        Task {
            try? await Task.sleep(for: .seconds(30))
            stopFindingMac()
        }
    }

    func stopFindingMac() {
        findMacSound?.stop()
        findMacSound = nil
        for device in devices.values { device.isBeingFound = false }
    }

    // MARK: Capabilities

    /// The phone turns a plugin on for this Mac only if its packet types appear here.
    static let capabilities = Capabilities(
        incoming: [
            PacketType.ping, PacketType.battery, PacketType.connectivityReport,
            PacketType.clipboard, PacketType.clipboardConnect,
            PacketType.notification, PacketType.share, PacketType.shareUpdate,
            PacketType.telephony, PacketType.smsMessages,
            PacketType.contactsResponseUIDs, PacketType.contactsResponseVCards,
            PacketType.findMyPhone, PacketType.sftp,
            PacketType.glasslinkScreenshot, PacketType.glasslinkClipboardImage, PacketType.glasslinkWallpaper,
            PacketType.glasslinkClipboardRequest,
        ],
        outgoing: [
            PacketType.ping, PacketType.clipboard, PacketType.clipboardConnect,
            PacketType.findMyPhone,
            PacketType.notificationRequest, PacketType.notificationReply, PacketType.notificationAction,
            PacketType.share, PacketType.telephonyMute,
            PacketType.smsRequest, PacketType.smsRequestConversations, PacketType.smsRequestConversation,
            PacketType.contactsRequestAllUIDs, PacketType.contactsRequestVCards,
            PacketType.sftpRequest, PacketType.glasslinkClipboardImage,
            PacketType.glasslinkClipboardRequest, PacketType.glasslinkWallpaperRequest,
        ]
    )

    static var isLaptop: Bool {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let list = info.flatMap { IOPSCopyPowerSourcesList($0)?.takeRetainedValue() as? [CFTypeRef] } ?? []
        return !list.isEmpty
    }
}
