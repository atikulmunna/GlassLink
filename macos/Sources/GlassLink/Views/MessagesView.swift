import SwiftUI

struct MessagesView: View {
    var device: PhoneDevice
    @State private var selection: Int64?
    @State private var search = ""
    @State private var composing = false

    private var filtered: [Conversation] {
        guard !search.isEmpty else { return device.conversations }
        return device.conversations.filter {
            device.title(for: $0).localizedCaseInsensitiveContains(search)
                || $0.latest.body.localizedCaseInsensitiveContains(search)
                || $0.addresses.contains { $0.contains(search) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            conversationList
                .frame(width: 290)
            Divider()
            if let id = selection, let conversation = device.conversations.first(where: { $0.threadId == id }) {
                ThreadView(device: device, conversation: conversation)
                    .id(id)
            } else {
                ContentUnavailableView("Select a Conversation", systemImage: "message",
                                       description: Text("Messages are sent through \(device.name)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem {
                Button("New Message", systemImage: "square.and.pencil") { composing = true }
                    .disabled(!device.isReady)
            }
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") { device.requestConversations() }
                    .disabled(!device.isReady)
            }
        }
        .sheet(isPresented: $composing) { NewMessageSheet(device: device) }
        .onAppear {
            if device.conversations.isEmpty { device.requestConversations() }
            if DemoData.showsSampleContent, selection == nil { selection = device.conversations.first?.threadId }
        }
        .onChange(of: device.conversations.first?.threadId) { _, first in
            // Screenshot mode fills in the sample conversations a moment after the view appears.
            if DemoData.showsSampleContent, selection == nil { selection = first }
        }
    }

    private var conversationList: some View {
        List(filtered, selection: $selection) { conversation in
            ConversationRow(device: device, conversation: conversation)
                .tag(conversation.threadId)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
        .overlay {
            if device.conversations.isEmpty {
                ContentUnavailableView {
                    Label("No Messages", systemImage: "message.badge")
                } description: {
                    Text(device.isConnected
                        ? "Grant KDE Connect permission to read SMS on \(device.name), then reload."
                        : "Connect \(device.name) to load messages.")
                }
            }
        }
    }
}

struct ConversationRow: View {
    var device: PhoneDevice
    var conversation: Conversation

    var body: some View {
        let title = device.title(for: conversation)
        let unread = !conversation.latest.isRead && !conversation.latest.isOutgoing
        HStack(spacing: 10) {
            Avatar(name: title, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.body.weight(unread ? .bold : .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.latest.date.shortRelative).font(.caption).foregroundStyle(.secondary)
                }
                Text((conversation.latest.isOutgoing ? "You: " : "") + conversation.latest.body)
                    .font(.callout)
                    .foregroundStyle(unread ? .primary : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            if unread { Circle().fill(.primary).frame(width: 7, height: 7).offset(x: -11) }
        }
    }
}

struct ThreadView: View {
    var device: PhoneDevice
    var conversation: Conversation
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var messages: [SMSMessage] { device.threads[conversation.threadId] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    if messages.count >= 60 {
                        Button("Load Earlier Messages") { device.requestThread(conversation.threadId, before: messages.first?.date) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .padding(.vertical, 10)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || message.date.timeIntervalSince(messages[index - 1].date) > 3600 {
                            Text(message.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                        Bubble(message: message)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .animation(.glass, value: messages.count)
            }
            .defaultScrollAnchor(.bottom)
            composer
        }
        .onAppear { device.requestThread(conversation.threadId) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(name: device.title(for: conversation), size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.title(for: conversation)).font(.headline).lineLimit(1)
                if device.title(for: conversation) != conversation.addresses.joined(separator: ", ") {
                    Text(conversation.addresses.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Text Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            Button("Send", systemImage: "arrow.up", action: send)
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !device.isReady)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.glass) { device.sendMessage(text, in: conversation) }
        draft = ""
    }
}

struct Bubble: View {
    var message: SMSMessage

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }
            Text(message.body)
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(message.isOutgoing ? AnyShapeStyle(Midnight.background) : AnyShapeStyle(.primary))
                .background(
                    message.isOutgoing ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .opacity(message.isPending ? 0.6 : 1)
                .help(message.date.formatted(date: .abbreviated, time: .shortened))
            if !message.isOutgoing { Spacer(minLength: 60) }
        }
    }
}

struct NewMessageSheet: View {
    var device: PhoneDevice
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Message").font(.title2.weight(.semibold))
            TextField("Phone number", text: $recipient)
                .textFieldStyle(.roundedBorder)
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") {
                    let addresses = recipient.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    device.sendMessage(text, to: addresses)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(recipient.isEmpty || text.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}
