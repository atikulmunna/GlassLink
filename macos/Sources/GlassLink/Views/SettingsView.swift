import KDEConnectKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Devices", systemImage: "smartphone") { DeviceSettings() }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("receiveClipboard") private var receiveClipboard = true
    @AppStorage("sendClipboard") private var sendClipboard = true
    @AppStorage("mirrorNotifications") private var mirrorNotifications = true
    @AppStorage("phoneScreenshots") private var phoneScreenshots = true
    @AppStorage("sendMacScreenshots") private var sendMacScreenshots = true
    @AppStorage("sendCopiedImages") private var sendCopiedImages = false
    @AppStorage("syncImageClipboard") private var syncImageClipboard = true
    @AppStorage("customHosts") private var customHosts = ""
    @AppStorage("downloadsFolder") private var downloadsFolder = ""
    @State private var name = ""

    var body: some View {
        Form {
            SwiftUI.Section {
                TextField("Name on your phone", text: $name)
                    .onSubmit { model.rename(to: name) }
            } footer: {
                Text("Letters, numbers and spaces; up to 32 characters.").foregroundStyle(.secondary)
            }

            SwiftUI.Section("Clipboard") {
                Toggle("Copy from phone to Mac", isOn: $receiveClipboard)
                Toggle("Copy from Mac to phone", isOn: $sendClipboard)
            }

            SwiftUI.Section {
                Toggle("Copy phone screenshots to this Mac's clipboard", isOn: $phoneScreenshots)
                    .onChange(of: phoneScreenshots) { _, on in
                        for device in model.pairedDevices { on ? device.requestFileAccess() : device.stopScreenshotSync() }
                    }
                Toggle("Copy this Mac's screenshots to the phone's clipboard", isOn: $sendMacScreenshots)
                Toggle("Copy and paste images between devices", isOn: $syncImageClipboard)
                Toggle("Phones using stock KDE Connect: send images as files instead", isOn: $sendCopiedImages)
            } header: {
                Text("Screenshots")
            } footer: {
                Text("Screenshots and images stay on the clipboard only; nothing is saved to your folders. Stock KDE Connect can't put images on the phone's clipboard, so for it they can arrive in Downloads instead.")
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Notifications") {
                Toggle("Show phone notifications in Notification Center", isOn: $mirrorNotifications)
            }

            SwiftUI.Section("Received Files") {
                LabeledContent("Save to") {
                    HStack {
                        Text(Prefs.downloadsFolder.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { downloadsFolder = url.path }
                        }
                    }
                }
            }

            SwiftUI.Section {
                TextField("IP addresses", text: $customHosts, prompt: Text("192.168.1.20, 10.0.0.5"))
                    .onSubmit { model.refresh() }
            } header: {
                Text("Network")
            } footer: {
                Text("If your network blocks discovery, list your phone's IP address here.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { name = model.localName }
        .onDisappear { if name != model.localName, !name.isEmpty { model.rename(to: name) } }
    }
}

private struct DeviceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            SwiftUI.Section("Paired") {
                if model.pairedDevices.isEmpty {
                    Text("No paired devices").foregroundStyle(.secondary)
                }
                ForEach(model.pairedDevices) { device in
                    HStack {
                        Label(device.name, systemImage: device.symbolName)
                        ConnectionDot(connected: device.isConnected)
                        Spacer()
                        Button("Unpair", role: .destructive) { device.unpair() }
                    }
                }
            }
            SwiftUI.Section("This Mac") {
                if let identity = model.identity {
                    LabeledContent("Device ID") { Text(identity.deviceId).font(.caption.monospaced()).textSelection(.enabled) }
                    LabeledContent("Certificate") {
                        Text(CertificateInfo.fingerprint(ofDER: identity.certificateDER).prefix(47) + "…")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Listening on") { Text("TCP \(model.provider?.tcpPort ?? 0), UDP \(LanLinkProvider.udpPort)") }
                }
            }
        }
        .formStyle(.grouped)
    }
}
