import SwiftUI

struct NotificationsView: View {
    var device: PhoneDevice

    var body: some View {
        Group {
            if device.notifications.isEmpty {
                ContentUnavailableView {
                    Label("No Notifications", systemImage: "bell.slash")
                } description: {
                    Text(device.isConnected
                        ? "New notifications from \(device.name) appear here. If none arrive, allow notification access for GlassLink in the phone's settings."
                        : "Connect \(device.name) to see its notifications.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(device.notifications) { notification in
                            NotificationCard(device: device, notification: notification)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .scale(scale: 0.92).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .animation(.glass, value: device.notifications.map(\.id))
                }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem {
                Button("Clear All", systemImage: "xmark.circle") {
                    withAnimation(.glass) { device.dismissAll() }
                }
                .disabled(!device.notifications.contains(where: \.isClearable) || !device.isReady)
                .help("Dismiss every clearable notification on the phone")
            }
        }
    }
}

struct NotificationCard: View {
    var device: PhoneDevice
    var notification: PhoneNotification
    @State private var hovering = false
    @State private var replying = false
    @State private var draft = ""
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AppIcon(image: notification.iconHash.flatMap { device.icons[$0] }, appName: notification.appName, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(notification.appName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(notification.time.shortRelative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !notification.title.isEmpty {
                        Text(notification.title).font(.headline).lineLimit(2)
                    }
                    if !notification.text.isEmpty {
                        Text(notification.text)
                            .foregroundStyle(.secondary)
                            .lineLimit(replying ? nil : 4)
                            .textSelection(.enabled)
                    }
                }
            }

            if !notification.actions.isEmpty || notification.replyId != nil {
                HStack(spacing: 8) {
                    if notification.replyId != nil {
                        Button("Reply") {
                            withAnimation(.glass) { replying.toggle() }
                            replyFocused = replying
                        }
                    }
                    ForEach(notification.actions, id: \.self) { action in
                        Button(action) { device.trigger(action, on: notification) }
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.leading, 48)
            }

            if replying, let replyId = notification.replyId {
                HStack(spacing: 8) {
                    TextField("Reply to \(notification.title.isEmpty ? notification.appName : notification.title)", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($replyFocused)
                        .onSubmit { send(replyId) }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                    Button("Send", systemImage: "arrow.up") { send(replyId) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.midnightProminent)
                        .buttonBorderShape(.circle)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.leading, 48)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .overlay(alignment: .topLeading) {
            if hovering, notification.isClearable {
                Button {
                    withAnimation(.glass) { device.dismiss(notification) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(x: -6, y: -6)
                .transition(.scale.combined(with: .opacity))
                .help("Dismiss on the phone")
            }
        }
        .onHover { over in withAnimation(.glass) { hovering = over } }
        .contextMenu {
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString([notification.title, notification.text].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
            }
            if notification.isClearable {
                Button("Dismiss on Phone") { withAnimation(.glass) { device.dismiss(notification) } }
            }
        }
    }

    private func send(_ replyId: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        device.reply(to: replyId, message: text)
        draft = ""
        withAnimation(.glass) { replying = false }
    }
}
