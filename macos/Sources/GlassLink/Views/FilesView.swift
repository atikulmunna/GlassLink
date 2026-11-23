import SwiftUI

struct FilesView: View {
    var device: PhoneDevice
    @State private var text = ""
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dropZone
                shareText
                if !device.transfers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Recent Transfers")
                        ForEach(device.transfers) { transfer in
                            TransferRow(transfer: transfer)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.glass, value: device.transfers.map(\.id))
                }
            }
            .padding(26)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Files")
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: targeted ? "arrow.down.doc.fill" : "arrow.up.doc")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
            Text("Drag files here to send them to \(device.name)")
                .font(.title3.weight(.medium))
            Text("They land in the phone's Downloads folder.")
                .foregroundStyle(.secondary)
            Button("Choose Files…") { FilePicker.sendFiles(to: device) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .glassEffect(targeted ? .regular.tint(Color.primary.opacity(0.12)) : .regular, in: .rect(cornerRadius: 28))
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(.glass, value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            RootView.loadURLs(providers) { device.send(files: $0) }
            return device.isReady
        }
        .disabled(!device.isReady)
    }

    private var shareText: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Send Text or a Link")
                HStack(spacing: 8) {
                    TextField("Paste a link to open it on the phone, or any text", text: $text)
                        .textFieldStyle(.plain)
                        .onSubmit(send)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: .capsule)
                    Button("Send", action: send)
                        .buttonStyle(.glass)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || !device.isReady)
                }
            }
        }
    }

    private func send() {
        device.share(text: text)
        text = ""
    }
}

struct TransferRow: View {
    var transfer: Transfer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transfer.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.filename).lineLimit(1).truncationMode(.middle)
                switch transfer.status {
                case .active:
                    ProgressView(value: transfer.fraction)
                        .progressViewStyle(.linear)
                        .animation(.linear(duration: 0.2), value: transfer.fraction)
                    Text("\(ByteCountFormatter.string(fromByteCount: transfer.done, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: transfer.total, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                case .finished:
                    Text("\(transfer.direction == .incoming ? "Received" : "Sent") · \(ByteCountFormatter.string(fromByteCount: transfer.total, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                case .failed(let reason):
                    Label("Failed: \(reason)", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.primary).lineLimit(2)
                }
            }
            Spacer()
            if transfer.status == .finished, transfer.direction == .incoming, let url = transfer.fileURL {
                Button("Show", systemImage: "magnifyingglass") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("Show in Finder")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
