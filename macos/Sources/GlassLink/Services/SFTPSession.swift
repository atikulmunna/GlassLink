import Foundation

/// A long-lived session with the phone's file server, driven through macOS's own `/usr/bin/sftp`.
///
/// Authentication mirrors the KDE Connect desktop: our device key (the phone accepts the key of
/// the paired certificate), with the one-time password from the phone as a fallback. Unlike the
/// desktop, the host key is pinned: it must be the key in the phone's paired certificate.
///
/// Commands are written to sftp's stdin; each batch ends with `lpwd`, whose reply line marks the
/// end of the output (sftp line-buffers stdout even on a pipe).
@MainActor
final class SFTPSession {
    struct Credentials {
        var host: String
        var port: Int
        var user: String
        var password: String
    }

    enum SessionError: Error, CustomStringConvertible {
        case exited(String)
        case timedOut

        var description: String {
            switch self {
            case .exited(let reason): reason.isEmpty ? "the connection closed" : reason
            case .timedOut: "the phone did not answer"
            }
        }
    }

    var onExit: ((String) -> Void)?

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = ""
    private var errorText = ""
    private var lines: [String] = []
    private var waiting: CheckedContinuation<[String], Error>?
    private var queue: [(String, Duration, CheckedContinuation<[String], Error>)] = []
    private var current = 0
    private var exited = false
    private static let sentinel = "Local working directory:"

    init(credentials: Credentials, deviceId: String, privateKey: URL, knownHostsLine: String, supportDirectory: URL) throws {
        let alias = "glasslink-\(deviceId)"
        let knownHosts = supportDirectory.appendingPathComponent("known_hosts-\(deviceId)")
        try Data("\(alias) \(knownHostsLine)\n".utf8).write(to: knownHosts, options: .atomic)

        // The password never touches the disk: the helper prints an environment variable.
        let askpass = supportDirectory.appendingPathComponent("askpass.sh")
        if !FileManager.default.fileExists(atPath: askpass.path) {
            try Data("#!/bin/sh\nprintf '%s\\n' \"$GLASSLINK_SFTP_PASSWORD\"\n".utf8).write(to: askpass, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = [
            "-q",
            "-P", String(credentials.port),
            "-i", privateKey.path,
            "-o", "IdentitiesOnly=yes",
            "-o", "PreferredAuthentications=publickey,password",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "HostKeyAlias=\(alias)",
            // Quoted: ssh splits this option on spaces ("Application Support").
            "-o", "UserKnownHostsFile=\"\(knownHosts.path)\"",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UpdateHostKeys=no",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "LogLevel=ERROR",
            "\(credentials.user)@\(credentials.host)",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = askpass.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["GLASSLINK_SFTP_PASSWORD"] = credentials.password
        environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.received(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.errorText += String(decoding: data, as: UTF8.self) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.terminated() }
        }
        try process.run()
    }

    /// Waits until the session is logged in.
    func connect() async throws {
        _ = try await run("", timeout: .seconds(20))
    }

    func close() {
        guard !exited else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data("bye\n".utf8))
        process.terminate()
    }

    /// Entry names in `directory`, newest first. Empty if it doesn't exist.
    func listNewestFirst(_ directory: String) async throws -> [String] {
        try await run("-ls -1t \(Self.quote(directory))")
            .map { ($0 as NSString).lastPathComponent }
            .filter { !$0.isEmpty && !$0.hasPrefix(".") }
    }

    func download(_ remote: String, to local: URL) async throws {
        _ = try await run("-get \(Self.quote(remote)) \(Self.quote(local.path))", timeout: .seconds(60))
    }

    // MARK: Plumbing

    private func run(_ command: String, timeout: Duration = .seconds(15)) async throws -> [String] {
        if exited { throw SessionError.exited(lastError) }
        return try await withCheckedThrowingContinuation { continuation in
            queue.append((command, timeout, continuation))
            pump()
        }
    }

    private func pump() {
        guard waiting == nil, !queue.isEmpty else { return }
        let (command, timeout, continuation) = queue.removeFirst()
        waiting = continuation
        lines = []
        current += 1
        let id = current
        // A command that never finishes means the link is dead: end the session.
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, self.current == id, self.waiting != nil else { return }
            self.errorText += "\nThe phone stopped responding.\n"
            self.process.terminate()
        }
        let text = (command.isEmpty ? "" : command + "\n") + "lpwd\n"
        do {
            try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
        } catch {
            waiting = nil
            continuation.resume(throwing: SessionError.exited(lastError))
        }
    }

    private func received(_ data: Data) {
        buffer += String(decoding: data, as: UTF8.self)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespaces)
            buffer.removeSubrange(...newline)
            if line.hasPrefix(Self.sentinel) {
                let result = lines
                lines = []
                let continuation = waiting
                waiting = nil
                continuation?.resume(returning: result)
                pump()
            } else if !line.hasPrefix("sftp>"), !line.isEmpty {
                lines.append(line)
            }
        }
    }

    private var lastError: String {
        errorText.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    }

    private func terminated() {
        appTrace("sftp exited (status \(process.terminationStatus)): \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        exited = true
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        let reason = lastError
        waiting?.resume(throwing: SessionError.exited(reason))
        waiting = nil
        for (_, _, continuation) in queue { continuation.resume(throwing: SessionError.exited(reason)) }
        queue = []
        onExit?(reason)
    }

    private static func quote(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
