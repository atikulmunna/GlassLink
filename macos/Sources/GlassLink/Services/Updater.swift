import AppKit
import CryptoKit
import Foundation
import KDEConnectKit

/// Checks GitHub for a newer GlassLink, then downloads, verifies and installs it in place.
///
/// The release's `SHA256SUMS` must carry a valid Ed25519 signature (`SHA256SUMS.sig`, made by
/// `tools/release-signing.swift`) from the key below, and the DMG must match its checksum, so only
/// releases signed by the GlassLink key are installed. The new app replaces this one after it quits,
/// then opens. The only request made is to GitHub's public releases API, with no identifying data.
@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        let version: String
        let notes: String
        let page: URL
        let dmg: URL
        let dmgName: String
        let sums: URL
        let signature: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var lastChecked: Date?
    @ObservationIgnored private var automaticChecks: Task<Void, Never>?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?

    /// Public half of ~/.glasslink/update-signing.key.
    static let publicKey = "fXcfXBe7X9z5t+qrvENAkKFdQD46ReYKrx6OI2WTtQA="
    /// Version and notes of the newest release. Served from the release's files, so it isn't limited
    /// like GitHub's API (60 anonymous requests an hour, shared by everyone behind one address).
    static let latestManifest = URL(string: "https://github.com/atikulmunna/GlassLink/releases/latest/download/latest.json")!
    /// Only for releases from before latest.json existed.
    static let latestRelease = URL(string: "https://api.github.com/repos/atikulmunna/GlassLink/releases/latest")!

    static func download(_ version: String, _ file: String) -> URL {
        URL(string: "https://github.com/atikulmunna/GlassLink/releases/download/v\(version)/\(file)")!
    }
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    /// Checks shortly after launch, then once a day, while automatic checks are on.
    func startAutomaticChecks() {
        guard automaticChecks == nil, !DemoData.isEnabled else { return }
        automaticChecks = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                if Prefs.checkForUpdates { await self?.check(quietly: true) }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    func check(quietly: Bool = false) async {
        guard !isBusy, available == nil || !quietly else { return }
        state = .checking
        do {
            let release = try await Self.fetchLatest()
            lastChecked = .now
            state = release.map(State.available) ?? .upToDate
        } catch {
            trace("update check failed: \(error)")
            state = quietly ? .idle : .failed("Couldn't check for updates. \(error.localizedDescription)")
        }
    }

    func install() async {
        guard let release = available else { return }
        state = .downloading(0)
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GlassLink Update \(release.version)")
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let sums = try await Self.fetch(release.sums)
            let signature = try await Self.fetch(release.signature)
            try Self.verify(sums, signature: signature)
            let expected = try Self.checksum(of: release.dmgName, in: sums)

            let dmg = try await download(release.dmg, to: folder.appendingPathComponent(release.dmgName))
            guard try Self.sha256(of: dmg) == expected else { throw UpdateError.corrupt }

            state = .installing
            let app = try await Self.copyApp(fromDiskImage: dmg, into: folder)
            try Self.checkBundle(app, version: release.version)
            try replaceAndRelaunch(with: app, diskImage: dmg)
        } catch {
            trace("update failed: \(error)")
            state = .failed("Couldn't install the update. \(error.localizedDescription)")
        }
    }

    // MARK: Checking

    /// The latest release if it's newer than this app, else nil.
    private static func fetchLatest() async throws -> Release? {
        let (version, notes) = try await latestVersion()
        guard isVersion(version, newerThan: currentVersion) else { return nil }
        let dmgName = "GlassLink-\(version).dmg"
        return Release(version: version, notes: notes,
                       page: URL(string: "https://github.com/atikulmunna/GlassLink/releases/tag/v\(version)")!,
                       dmg: download(version, dmgName), dmgName: dmgName,
                       sums: download(version, "SHA256SUMS"), signature: download(version, "SHA256SUMS.sig"))
    }

    private static func latestVersion() async throws -> (version: String, notes: String) {
        struct Manifest: Decodable {
            let version: String
            let notes: String?
        }
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: try await fetch(latestManifest))
            return (manifest.version, manifest.notes ?? "")
        } catch UpdateError.rateLimited {
            throw UpdateError.rateLimited
        } catch {
            // Releases before latest.json: ask the API instead.
            struct APIRelease: Decodable {
                let tag_name: String
                let body: String?
            }
            let release = try JSONDecoder().decode(APIRelease.self, from: try await fetch(latestRelease, json: true))
            let tag = release.tag_name
            return (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, release.body ?? "")
        }
    }

    private static func fetch(_ url: URL, json: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("GlassLink-Updater", forHTTPHeaderField: "User-Agent")
        if json { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 429 { throw UpdateError.rateLimited }
        guard status == 200 else { throw UpdateError.server }
        return data
    }

    /// Compares dotted versions numerically ("0.10.0" is newer than "0.9.3").
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split { !$0.isNumber }.map { Int($0) ?? 0 } }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Verifying

    private static func verify(_ sums: Data, signature: Data) throws {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let text = String(data: signature, encoding: .utf8),
              let signatureData = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(signatureData, for: sums)
        else { throw UpdateError.unsigned }
    }

    private static func checksum(of file: String, in sums: Data) throws -> String {
        let lines = String(decoding: sums, as: UTF8.self).split(separator: "\n")
        for line in lines {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count == 2, fields[1] == file { return String(fields[0]).lowercased() }
        }
        throw UpdateError.incomplete
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func checkBundle(_ app: URL, version: String) throws {
        let bundle = Bundle(url: app)
        guard bundle?.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
        else { throw UpdateError.corrupt }
    }

    // MARK: Installing

    private func download(_ url: URL, to destination: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.setValue("GlassLink-Updater", forHTTPHeaderField: "User-Agent")
            let task = URLSession.shared.downloadTask(with: request) { temporary, response, error in
                if let error { return continuation.resume(throwing: error) }
                guard let temporary, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return continuation.resume(throwing: UpdateError.server)
                }
                do {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    if case .downloading = self?.state { self?.state = .downloading(fraction) }
                }
            }
            task.resume()
        }
    }

    private static func copyApp(fromDiskImage dmg: URL, into folder: URL) async throws -> URL {
        let mount = folder.appendingPathComponent("mount")
        let app = folder.appendingPathComponent("GlassLink.app")
        try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer { Task.detached { try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) } }
        try await run("/usr/bin/ditto", [mount.appendingPathComponent("GlassLink.app").path, app.path])
        return app
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw UpdateError.installFailed }
            return process.terminationStatus
        }.value
    }

    /// Quits, then a small script swaps the app bundle (keeping the old one if the copy fails) and opens it.
    private func replaceAndRelaunch(with app: URL, diskImage: URL) throws {
        let current = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            // Not allowed to write there (for example a standard account and /Applications): let the
            // person drag it over themselves.
            NSWorkspace.shared.open(diskImage)
            state = .failed("GlassLink can't replace itself in \(current.deletingLastPathComponent().path). The new version is open in Finder: drag it to Applications.")
            return
        }
        let process = Self.relaunchProcess(dest: current.path, newApp: app.path, viaLaunchd: true)
        try process.run()
        NSApp.terminate(nil)
    }

    /// After this process quits: optionally swap in `newApp`, then reopen GlassLink.
    ///
    /// Reopening with `open` straight from this helper (a child of the old app) left the new copy
    /// without local network access: incoming connections worked, but its announcements never
    /// reached the phone until a normal restart. Going through launchd (a one-shot job in the
    /// person's session) starts it the way the Dock or Finder would.
    static func relaunchProcess(dest: String, newApp: String?, viaLaunchd: Bool) -> Process {
        let label = "io.github.atikulmunna.glasslink.relaunch"
        let reopen = viaLaunchd ? """
            plist="${TMPDIR:-/tmp}/\(label).plist"
            cat > "$plist" <<PLIST
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>\(label)</string>
              <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>$DEST</string></array>
              <key>RunAtLoad</key><true/>
            </dict></plist>
            PLIST
            launchctl bootout "gui/$(id -u)/\(label)" 2>/dev/null
            launchctl bootstrap "gui/$(id -u)" "$plist" || open "$DEST"
            sleep 10
            launchctl bootout "gui/$(id -u)/\(label)" 2>/dev/null
            rm -f "$plist"
            """ : """
            open "$DEST"
            """
        let script = """
        while kill -0 "$OLD_PID" 2>/dev/null; do sleep 0.2; done
        if [ -n "$NEW" ]; then
          backup="$DEST.previous"
          rm -rf "$backup"
          if mv "$DEST" "$backup"; then
            if ditto "$NEW" "$DEST"; then rm -rf "$backup"; else rm -rf "$DEST"; mv "$backup" "$DEST"; fi
          fi
          xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        fi
        # macOS registers a replaced app for local network access a moment after the swap.
        sleep 3
        \(reopen)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = ["OLD_PID": String(ProcessInfo.processInfo.processIdentifier), "DEST": dest,
                               "NEW": newApp ?? "", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "TMPDIR": NSTemporaryDirectory()]
        return process
    }

    /// Test hook for the reopen step alone: `defaults write io.github.atikulmunna.glasslink
    /// debugRelaunch open` (the old way) or `launchd`, then open GlassLink normally. About 15
    /// seconds later it quits and reopens itself that way, once.
    func runDebugRelaunchIfAsked() {
        guard let method = UserDefaults.standard.string(forKey: "debugRelaunch") else { return }
        UserDefaults.standard.removeObject(forKey: "debugRelaunch")
        Task {
            try? await Task.sleep(for: .seconds(15))
            trace("debug relaunch via \(method)")
            try? Self.relaunchProcess(dest: Bundle.main.bundlePath, newApp: nil, viaLaunchd: method == "launchd").run()
            NSApp.terminate(nil)
        }
    }

    enum UpdateError: LocalizedError {
        case server, rateLimited, incomplete, unsigned, corrupt, installFailed

        var errorDescription: String? {
            switch self {
            case .server: "GitHub didn't answer. Check your internet connection."
            case .rateLimited: "GitHub is limiting requests from your network right now. Try again later."
            case .incomplete: "The release is missing its download or checksums."
            case .unsigned: "The release isn't signed with GlassLink's key, so it wasn't installed."
            case .corrupt: "The download didn't match its checksum."
            case .installFailed: "Opening the downloaded disk image failed."
            }
        }
    }
}

/// "Check for Updates…" from the GlassLink menu: says what it found, in an alert.
@MainActor
enum UpdatePrompt {
    static func checkNow(_ updater: Updater) {
        Task {
            await updater.check()
            let alert = NSAlert()
            switch updater.state {
            case .available(let release):
                alert.messageText = "GlassLink \(release.version) is available"
                alert.informativeText = "You have \(Updater.currentVersion). " + summary(of: release.notes)
                alert.addButton(withTitle: "Install and Reopen")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { await updater.install() }
                if case .failed(let reason) = updater.state { show("The update didn't install", reason) }
            case .upToDate:
                show("You're up to date", "GlassLink \(Updater.currentVersion) is the latest version.")
            case .failed(let reason):
                show("Couldn't check for updates", reason)
            default:
                break
            }
        }
    }

    private static func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    /// The release notes as plain text, short enough for an alert.
    private static func summary(of notes: String) -> String {
        let plain = notes.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .split(separator: "\n").filter { !$0.hasPrefix("**Downloads") && !$0.hasPrefix("#") }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.count > 700 ? String(plain.prefix(700)) + "…" : plain
    }
}
