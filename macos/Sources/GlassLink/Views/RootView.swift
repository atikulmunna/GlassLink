import SwiftUI
import UniformTypeIdentifiers

enum Section: String, Hashable, CaseIterable, Identifiable {
    case overview, messages, notifications, files
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .messages: "Messages"
        case .notifications: "Notifications"
        case .files: "Files"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "smartphone"
        case .messages: "message"
        case .notifications: "bell"
        case .files: "folder"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("section") private var section: Section = .overview
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if let device = model.current {
                NavigationSplitView {
                    Sidebar(device: device, section: $section)
                        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
                } detail: {
                    detail(for: device)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay { if dropTargeted { DropOverlay(device: device) } }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    Self.loadURLs(providers) { device.send(files: $0) }
                    return device.isReady
                }
                .overlay(alignment: .top) { CallBanner(device: device) }
            } else {
                WelcomeView()
            }
        }
        .overlay { FindMacOverlay() }
        .sheet(item: Binding(get: { model.pairingRequest }, set: { model.pairingRequest = $0 })) { device in
            PairRequestSheet(device: device)
        }
        .animation(.glass, value: model.current?.id)
        .onAppear {
            // Demo/screenshot aid: GLASSLINK_SECTION=messages opens that screen.
            if DemoData.isEnabled, let name = ProcessInfo.processInfo.environment["GLASSLINK_SECTION"],
               let start = Section(rawValue: name) { section = start }
        }
    }

    @ViewBuilder
    private func detail(for device: PhoneDevice) -> some View {
        switch section {
        case .overview: OverviewView(device: device, section: $section)
        case .messages: MessagesView(device: device)
        case .notifications: NotificationsView(device: device)
        case .files: FilesView(device: device)
        }
    }

    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.withLock { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { completion(urls) } }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    var device: PhoneDevice
    @Binding var section: Section

    var body: some View {
        List(selection: Binding(get: { section }, set: { if let new = $0 { section = new } })) {
            DeviceHeader(device: device)
                .listRowSeparator(.hidden)
                .selectionDisabled()

            ForEach(Section.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(badge(for: item))
                    .tag(item)
            }

            if model.pairedDevices.count > 1 {
                SwiftUI.Section("Devices") {
                    ForEach(model.pairedDevices) { other in
                        Button {
                            withAnimation(.glass) { model.selectedDeviceId = other.id }
                        } label: {
                            HStack {
                                Label(other.name, systemImage: other.symbolName)
                                Spacer()
                                ConnectionDot(connected: other.isConnected)
                            }
                        }
                        .buttonStyle(.plain)
                        .selectionDisabled()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Midnight.background)
    }

    private func badge(for section: Section) -> Int {
        switch section {
        case .notifications: device.notifications.count
        case .messages: device.conversations.filter { !$0.latest.isRead && !$0.latest.isOutgoing }.count
        case .files: device.transfers.filter { $0.status == .active }.count
        case .overview: 0
        }
    }
}

struct DeviceHeader: View {
    var device: PhoneDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbolName)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    ConnectionDot(connected: device.isConnected)
                    Text(device.isConnected ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if device.battery != nil {
                        BatteryGauge(battery: device.battery, compact: true)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Overlays

struct DropOverlay: View {
    var device: PhoneDevice

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.08))
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 44, weight: .light))
                    .symbolEffect(.bounce, options: .repeating)
                Text(device.isReady ? "Drop to send to \(device.name)" : "\(device.name) isn't connected")
                    .font(.title3.weight(.medium))
            }
            .padding(40)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

struct CallBanner: View {
    var device: PhoneDevice

    var body: some View {
        if let call = device.call {
            HStack(spacing: 14) {
                Avatar(name: call.name, size: 40, image: call.photo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.kind == .ringing ? "Incoming call" : "On a call")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(call.name).font(.headline)
                    if call.name != call.number, !call.number.isEmpty {
                        Text(call.number).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 20)
                if call.kind == .ringing {
                    Button("Silence", systemImage: "bell.slash.fill") { device.muteRinger() }
                        .buttonStyle(.glass)
                }
                Image(systemName: "phone.fill")
                    .foregroundStyle(.primary)
                    .symbolEffect(.wiggle, options: .repeating, isActive: call.kind == .ringing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 460)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct FindMacOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let device = model.devices.values.first(where: \.isBeingFound) {
            VStack(spacing: 16) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 52))
                    .symbolEffect(.pulse, options: .repeating)
                Text("\(device.name) is looking for this Mac").font(.title2.weight(.semibold))
                Button("Found It") { model.stopFindingMac() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(36)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}
