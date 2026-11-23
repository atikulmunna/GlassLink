import AppKit
import Foundation
import KDEConnectKit

enum ScreenshotSyncStatus: Equatable {
    case off
    case connecting
    case watching(folder: String)
    /// The GlassLink Android app pushes screenshots itself; nothing to poll.
    case pushed
    /// The phone refused, usually because KDE Connect lacks "All files access".
    case needsPermission(String)
    case failed(String)
}

/// Phone → Mac: watches the phone's screenshot folder over SFTP. Each new screenshot is
/// downloaded, put on the Mac clipboard, and shown as a floating thumbnail.
@MainActor
final class PhoneScreenshotWatcher {
    private weak var device: PhoneDevice?
    private var session: SFTPSession?
    private var folder: String?
    private var known: Set<String> = []
    private var polling: Task<Void, Never>?
    private var stopped = false

    /// Where phones keep screenshots: Samsung uses DCIM, stock Android and most others Pictures.
    private static let candidates = ["DCIM/Screenshots", "Pictures/Screenshots"]

    init(device: PhoneDevice) {
        self.device = device
    }

    func start(reply packet: NetworkPacket, link: DeviceLink, app: AppModel) {
        if let message = packet["errorMessage"]?.string {
            device?.screenshotStatus = .needsPermission(message)
            return
        }
        guard let host = packet["ip"]?.string ?? link.remoteHost,
              let port = packet["port"]?.int,
              let hostKey = SSHPublicKey.openSSH(fromSPKI: link.publicKeySPKI)
        else {
            device?.screenshotStatus = .failed("The phone's file server didn't send its address.")
            return
        }
        let roots = packet["multiPaths"]?.stringArray.nilIfEmpty ?? [packet["path"]?.string ?? "/storage/emulated/0"]
        let credentials = SFTPSession.Credentials(host: host, port: Int(port), user: packet["user"]?.string ?? "kdeconnect",
                                                  password: packet["password"]?.string ?? "")
        device?.screenshotStatus = .connecting
        do {
            let session = try SFTPSession(credentials: credentials, deviceId: link.deviceId,
                                          privateKey: app.identityDirectory.appendingPathComponent("private-key.pem"),
                                          knownHostsLine: hostKey, supportDirectory: app.supportDirectory)
            session.onExit = { [weak self] reason in self?.sessionEnded(reason) }
            self.session = session
            Task { await self.begin(session: session, roots: roots) }
        } catch {
            device?.screenshotStatus = .failed(String(describing: error))
        }
    }

    func stop() {
        stopped = true
        polling?.cancel()
        session?.close()
        session = nil
    }

    private func begin(session: SFTPSession, roots: [String]) async {
        do {
            try await session.connect()
            // Find the screenshot folder and remember what's already there.
            for root in roots {
                for candidate in Self.candidates {
                    let path = (root as NSString).appendingPathComponent(candidate)
                    let names = try await session.listNewestFirst(path)
                    if !names.isEmpty {
                        folder = path
                        known = Set(names)
                        break
                    }
                }
                if folder != nil { break }
            }
            guard let folder else {
                device?.screenshotStatus = .failed("No Screenshots folder on the phone yet. Take one screenshot, then refresh.")
                return
            }
            device?.screenshotStatus = .watching(folder: folder)
            device?.fileServerFailures = 0
            polling = Task { [weak self] in await self?.poll(session: session, folder: folder) }
        } catch {
            device?.screenshotStatus = .failed(String(describing: error))
        }
    }

    private func poll(session: SFTPSession, folder: String) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let names = try? await session.listNewestFirst(folder) else { continue }
            let fresh = names.prefix(5).filter { !known.contains($0) && Self.isImage($0) }
            known.formUnion(names)
            for name in fresh.reversed() {
                // The phone may still be writing the file; give it a moment.
                try? await Task.sleep(for: .milliseconds(600))
                await fetch(name, from: folder, session: session)
            }
        }
    }

    private func fetch(_ name: String, from folder: String, session: SFTPSession) async {
        guard let device else { return }
        let destination = ScreenshotFiles.destination(for: name)
        for attempt in 0..<3 {
            try? FileManager.default.removeItem(at: destination)
            try? await session.download((folder as NSString).appendingPathComponent(name), to: destination)
            if let image = NSImage(contentsOf: destination), image.isValid {
                device.app?.clipboard.setImageFromPhone(image, file: destination)
                ScreenshotToast.show(image: image, file: destination, source: device.name, copied: true)
                return
            }
            try? await Task.sleep(for: .milliseconds(700 * (attempt + 1)))
        }
    }

    private func sessionEnded(_ reason: String) {
        polling?.cancel()
        session = nil
        guard !stopped, let device else { return }
        device.screenshotStatus = .failed(reason.isEmpty ? "Disconnected from the phone's files." : reason)
        // The phone may close an idle file server: ask for a new one, backing off on repeated failures.
        device.fileServerFailures += 1
        let failures = device.fileServerFailures
        guard failures <= 6 else { return }
        Task { [weak device] in
            try? await Task.sleep(for: .seconds(min(120, 5 * (1 << (failures - 1)))))
            device?.requestFileAccess()
        }
    }

    private static func isImage(_ name: String) -> Bool {
        ["png", "jpg", "jpeg", "webp", "heic"].contains((name as NSString).pathExtension.lowercased())
    }
}

/// Mac → phone: Spotlight marks every screenshot (`kMDItemIsScreenCapture`), wherever it was
/// saved, so new ones can go to the phone straight away.
@MainActor
final class MacScreenshotWatcher: NSObject {
    var onScreenshot: ((URL) -> Void)?
    private let query = NSMetadataQuery()
    private let launched = Date()
    private var seen: Set<String> = []

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate > %@", launched as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(self, selector: #selector(updated(_:)), name: .NSMetadataQueryDidUpdate, object: query)
        query.start()
    }

    @objc private func updated(_ notification: Notification) {
        let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
        for item in added {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String, !seen.contains(path) else { continue }
            seen.insert(path)
            onScreenshot?(URL(fileURLWithPath: path))
        }
    }
}

/// Images from the phone live only on the clipboard. This cache keeps the latest few as files
/// just so the floating thumbnail can be dragged or opened; nothing is saved to the user's folders.
enum ScreenshotFiles {
    static var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("io.github.atikulmunna.glasslink/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func destination(for name: String) -> URL {
        prune(keeping: 4)
        return folder.appendingPathComponent((name as NSString).lastPathComponent)
    }

    private static func prune(keeping count: Int) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for file in sorted.dropFirst(count) { try? fm.removeItem(at: file) }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
