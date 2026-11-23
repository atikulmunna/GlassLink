import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A floating glass thumbnail in the corner of the screen, like macOS's own screenshot preview:
/// drag it into any app, click to open, or let it slide away.
@MainActor
enum ScreenshotToast {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(image: NSImage, file: URL, source: String, copied: Bool) {
        dismiss(animated: false)
        let size = NSSize(width: 260, height: 230)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: ToastView(image: image, file: file, source: source, copied: copied,
                                                              onHover: { hovering in hovering ? pause() : scheduleDismiss() },
                                                              onClose: { dismiss(animated: true) }))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.minY + 16))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        scheduleDismiss()
    }

    private static func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            dismiss(animated: true)
        }
    }

    private static func pause() {
        dismissTask?.cancel()
    }

    static func dismiss(animated: Bool) {
        dismissTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
    }
}

private struct ToastView: View {
    /// Drags offer a temporary copy, so dropping into Finder can't move the original away.
    static func copyProvider(for file: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = file.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: file.pathExtension) ?? .image
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(file.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file, to: copy)
                completion(copy, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    var image: NSImage
    var file: URL
    var source: String
    var copied: Bool
    var onHover: (Bool) -> Void
    var onClose: () -> Void
    @State private var appeared = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 150)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .onDrag { Self.copyProvider(for: file) }
                .onTapGesture { NSWorkspace.shared.open(file) }
                .help("Drag into any app, or click to open")
            HStack(spacing: 6) {
                Image(systemName: copied ? "doc.on.clipboard.fill" : "smartphone")
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(copied ? "Copied from \(source)" : "From \(source)").font(.caption.weight(.semibold))
                    Text("Paste with ⌘V · drag to save").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topLeading) {
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(x: -5, y: -5)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(8)
        .scaleEffect(appeared ? 1 : 0.85, anchor: .bottomTrailing)
        .offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(.glass) { appeared = true } }
        .onHover { over in
            withAnimation(.glass) { hovering = over }
            onHover(over)
        }
    }
}
