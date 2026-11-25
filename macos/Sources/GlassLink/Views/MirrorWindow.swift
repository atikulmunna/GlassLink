import SwiftUI

/// The "Phone Screen" window: the phone's live screen in a phone-shaped frame, with Back, Home and
/// Recents underneath. Opening it asks the phone to share; closing it stops sharing.
struct MirrorWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let device = model.current {
            MirrorContent(device: device, controller: device.mirror)
        } else {
            ContentUnavailableView("No Phone Paired", systemImage: "smartphone.slash",
                                   description: Text("Pair a phone running GlassLink for Android first."))
                .frame(width: 380, height: 600)
        }
    }
}

private struct MirrorContent: View {
    var device: PhoneDevice
    var controller: MirrorController

    private var showsVideo: Bool { controller.state == .streaming || controller.state == .connecting }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.black)
                if showsVideo {
                    MirrorVideoView(controller: controller)
                        .clipShape(.rect(cornerRadius: 30, style: .continuous))
                        .padding(7)
                        .transition(.opacity)
                }
                if controller.state != .streaming {
                    status
                        .padding(28)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .aspectRatio(controller.videoSize, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if controller.inputUnavailable, controller.state == .streaming {
                    Label("Turn on GlassLink in the phone's Accessibility settings to tap and swipe from here",
                          systemImage: "hand.tap")
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .padding(.top, 34)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.glass, value: controller.inputUnavailable)
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            .animation(.glass, value: controller.state)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 26) {
                    GlassActionButton(title: "Back", symbol: "chevron.backward", trigger: 0, size: 44) { controller.back() }
                    GlassActionButton(title: "Home", symbol: "circle", trigger: 0, size: 44) { controller.home() }
                    GlassActionButton(title: "Recents", symbol: "square.on.square", trigger: 0, size: 44) { controller.recents() }
                }
            }
            .disabled(controller.state != .streaming)

            if controller.state == .streaming {
                Label(controller.typingUnavailable ? "Typing from your Mac needs Android 14 or later"
                                                   : "Tap a text field, then type on your Mac",
                      systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 400, maxWidth: .infinity, minHeight: 560, idealHeight: 860, maxHeight: .infinity)
        .navigationTitle(device.name)
        .toolbar {
            ToolbarItem {
                if controller.isActive {
                    Button("Stop Mirroring", systemImage: "stop.fill") { controller.stop() }
                } else {
                    Button("Mirror", systemImage: "rectangle.on.rectangle") { controller.start() }
                        .disabled(!device.supportsMirroring || !device.isReady)
                }
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 14) {
            switch controller.state {
            case .idle:
                statusIcon("rectangle.on.rectangle")
                Text(device.supportsMirroring ? "Mirror \(device.name)" : "Mirroring needs GlassLink for Android")
                    .font(.headline)
                if device.supportsMirroring {
                    Button("Start Mirroring") { controller.start() }.buttonStyle(.midnightProminent)
                }
            case .asking:
                statusIcon("hand.tap")
                Text("Tap Start on \(device.name)").font(.headline)
                Text("Share the entire screen, or just one app.")
                    .font(.callout).foregroundStyle(.secondary)
                ProgressView().controlSize(.small).padding(.top, 4)
            case .connecting:
                ProgressView()
                Text("Connecting…").font(.callout).foregroundStyle(.secondary)
            case .declined:
                statusIcon("xmark.circle")
                Text("Screen sharing was declined").font(.headline)
                Button("Try Again") { controller.start() }.buttonStyle(.midnightProminent)
            case .ended(let reason):
                statusIcon("rectangle.on.rectangle.slash")
                Text(reason).font(.headline).multilineTextAlignment(.center)
                Button("Mirror Again") { controller.start() }.buttonStyle(.midnightProminent)
            case .streaming:
                EmptyView()
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .environment(\.colorScheme, .dark)
    }

    private func statusIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(.white.opacity(0.85))
            .symbolEffect(.pulse, options: .repeating, isActive: controller.state == .asking)
    }
}

/// Phone menu item: opens the Phone Screen window.
struct MirrorCommand: View {
    var model: AppModel // menu commands don't get the window's environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Mirror Phone Screen") { openWindow(id: "mirror") }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(model.current?.supportsMirroring != true)
    }
}
