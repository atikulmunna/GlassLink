import AppKit
import SwiftUI

@main
struct GlassLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("GlassLink", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
                .midnightWindow()
        }
        .defaultSize(width: 1040, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdatePrompt.checkNow(model.updater) }
                    .disabled(model.updater.isBusy)
            }
            CommandGroup(after: .newItem) {
                Button("Send Files…") { FilePicker.sendFiles(to: model.current) }
                    .keyboardShortcut("o")
                    .disabled(model.current?.isReady != true)
            }
            CommandMenu("Phone") {
                Button("Ring Phone") { model.current?.ring() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Send Clipboard") { model.current?.sendClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Get Phone's Clipboard") { model.current?.requestPhoneClipboard() }
                    .disabled(model.current?.supportsClipboardRequest != true)
                Button("Wave at Phone") { model.current?.ping() }
                MirrorCommand(model: model)
                Divider()
                Button("Refresh Connection") { model.refresh() }
                    .keyboardShortcut("r")
            }
        }

        Window("Phone Screen", id: "mirror") {
            MirrorWindow()
                .environment(model)
                .midnightWindow()
        }
        .defaultSize(width: 400, height: 860)

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .tint(.primary)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .tint(.primary)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await AppModel.shared.start() }
    }

    /// Closing the window keeps the phone connected; the menu bar item stays.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stop() }
    }
}

enum FilePicker {
    @MainActor
    static func sendFiles(to device: PhoneDevice?) {
        guard let device, device.isReady else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Send"
        panel.message = "Choose files to send to \(device.name)"
        if panel.runModal() == .OK { device.send(files: panel.urls) }
    }
}
