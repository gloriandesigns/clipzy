//
//  Clipzy.swift
//  Clipzy additions: global hotkey clipboard capture + multi-file drag source.
//

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let clipzyCaptured = Notification.Name("wiki.clipzy.captured")
}

import Pow

extension AnyTransition {
    /// shared delete effect: blur-out + fade (BlurIn reversed)
    static var clipzyBlurOut: AnyTransition {
        .movingParts.blur(radius: 10).combined(with: .opacity)
    }
}

// MARK: - Floating text preview (center of screen)

enum PreviewContent {
    case text(String)
    case image(NSImage, name: String)

    // identity drives the crossfade between different copies
    var id: String {
        switch self {
        case let .text(t): "t:\(t.hashValue)"
        case let .image(_, name): "i:\(name)"
        }
    }
}

private struct PreviewCard: View {
    let content: PreviewContent

    var body: some View {
        Group {
            switch content {
            case let .text(text):
                Text(text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(24)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 520, alignment: .leading)
            case let .image(image, name):
                VStack(spacing: 10) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 480, maxHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(name)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private final class PreviewState: ObservableObject {
    @Published var content: PreviewContent?
}

private struct PreviewRoot: View {
    @ObservedObject var state: PreviewState

    var body: some View {
        ZStack {
            if let content = state.content {
                PreviewCard(content: content)
                    .id(content.id)
                    .transition(.opacity.combined(with: .movingParts.blur(radius: 14)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: state.content?.id)
        .frame(width: 660, height: 600)
    }
}

final class TextPreviewPanel {
    static let shared = TextPreviewPanel()
    private var panel: NSPanel?
    private let state = PreviewState()

    func show(text: String) {
        show(content: .text(text))
    }

    // one persistent transparent panel; content crossfades (blur+fade) inside it
    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = CGSize(width: 660, height: 600)
        let panel = NSPanel(
            contentRect: .init(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // card draws its own look; panel shadow would pop
        panel.level = .statusBar + 9
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PreviewRoot(state: state))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(.init(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            ))
        }
        self.panel = panel
        return panel
    }

    func show(content: PreviewContent) {
        ensurePanel().orderFrontRegardless()
        state.content = content
    }

    func hide() {
        state.content = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, state.content == nil else { return }
            panel?.orderOut(nil)
        }
    }

    /// brief toast, auto-hides
    func flash(_ text: String) {
        show(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.hide()
        }
    }
}

// MARK: - ⌘⇧C clipboard capture

enum ClipboardCapture {
    private static var lastChangeCount = NSPasteboard.general.changeCount
    private static var watchTimer: Timer?
    private static var pendingRemoteChangeCount: Int?
    private static var keyCancellable: AnyCancellable?

    /// call after Clipzy itself writes the pasteboard, else the watcher re-captures it
    static func ignoreCurrentPasteboard() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Auto-capture: poll pasteboard changeCount, store every copy.
    static func startWatching() {
        // ponytail: 1s polling — NSPasteboard has no change notification API
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount != lastChangeCount else { return }
            lastChangeCount = pasteboard.changeCount
            // skip password-manager / concealed content
            let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
            if pasteboard.types?.contains(where: { $0 == concealed || $0 == transient }) == true { return }
            // Universal Clipboard from another device: hold off until the user
            // actually pastes it here (⌘V) — don't hoover every iPhone copy
            let remote = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")
            if pasteboard.types?.contains(remote) == true {
                pendingRemoteChangeCount = pasteboard.changeCount
                return
            }
            pendingRemoteChangeCount = nil
            captureNow()
        }

        // ⌘V with a pending other-device clipboard → capture it
        // (global paste detection needs Accessibility; local pastes always work)
        keyCancellable = EventMonitors.shared.keyDown.sink { event in
            guard event.keyCode == 9, event.modifierFlags.contains(.command),
                  let pending = pendingRemoteChangeCount,
                  NSPasteboard.general.changeCount == pending
            else { return }
            pendingRemoteChangeCount = nil
            captureNow()
        }
    }

    static func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            ClipboardCapture.captureNow()
            return noErr
        }, 1, &eventType, nil, nil)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x5053_5459, id: 1) // 'PSTY'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
    }

    static func captureNow() {
        let pasteboard = NSPasteboard.general
        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        let image = fileURLs.isEmpty ? NSImage(pasteboard: pasteboard) : nil
        let text = pasteboard.string(forType: .string)

        DispatchQueue.global().async {
            var urls: [URL] = fileURLs
            if urls.isEmpty {
                let dir = temporaryDirectory
                    .appendingPathComponent("ClipboardCapture")
                    .appendingPathComponent(UUID().uuidString)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let stamp = Self.stampFormatter.string(from: Date())
                if let image, let data = image.tiffRepresentation
                    .flatMap({ NSBitmapImageRep(data: $0) })?
                    .representation(using: .png, properties: [:])
                {
                    let url = dir.appendingPathComponent("Image \(stamp).png")
                    try? data.write(to: url)
                    urls = [url]
                } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let isLink = text.hasPrefix("http://") || text.hasPrefix("https://")
                    let name = isLink ? "Link \(stamp).webloc" : "Text \(stamp).txt"
                    let url = dir.appendingPathComponent(name)
                    if isLink {
                        let plist = ["URL": text]
                        try? (try? PropertyListSerialization.data(
                            fromPropertyList: plist, format: .xml, options: 0
                        ))?.write(to: url)
                    } else {
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                    }
                    urls = [url]
                }
            }
            guard !urls.isEmpty else { return }
            do {
                let items = try urls.map { try TrayDrop.DropItem(url: $0) }
                DispatchQueue.main.async {
                    items.forEach { TrayDrop.shared.items.updateOrInsert($0, at: 0) }
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    NotificationCenter.default.post(name: .clipzyCaptured, object: nil)
                }
            } catch {
                DispatchQueue.main.async { NSAlert.popError(error) }
            }
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH.mm.ss"
        return formatter
    }()
}

// MARK: - Copy to clipboard

enum ClipzyCopy {
    /// file URL + (for text) string rep on each pasteboard item:
    /// Finder pastes files, editors paste text
    static func copy(_ items: [TrayDrop.DropItem]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let pbItems: [NSPasteboardItem] = items.map { item in
            let p = NSPasteboardItem()
            if let text = item.previewText {
                // text-only: a file-url rep makes editors paste a .txt attachment
                p.setString(text, forType: .string)
            } else {
                p.setString(item.storageURL.absoluteString, forType: .fileURL)
            }
            return p
        }
        pasteboard.writeObjects(pbItems)
        ClipboardCapture.ignoreCurrentPasteboard()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        TextPreviewPanel.shared.flash(items.count == 1 ? "Copied ✓" : "Copied \(items.count) items ✓")
    }
}

// MARK: - Multi-file drag source

private final class MultiDragNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onDragStarted: (() -> Void)?
    var onTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    private var mouseDownLocation: NSPoint = .zero
    private var didDrag = false
    private var pendingTap: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didDrag = false
        if event.clickCount > 1 {
            pendingTap?.cancel()
            pendingTap = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        if event.clickCount >= 2 {
            pendingTap?.cancel()
            pendingTap = nil
            onDoubleTap?()
        } else if onDoubleTap != nil {
            // delay single tap so a double-click can cancel it
            let work = DispatchWorkItem { [weak self] in self?.onTap?() }
            pendingTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else {
            onTap?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        let delta = hypot(
            event.locationInWindow.x - mouseDownLocation.x,
            event.locationInWindow.y - mouseDownLocation.y
        )
        guard delta > 4 else { return }
        didDrag = true
        guard !urls.isEmpty else { return }
        let location = convert(event.locationInWindow, from: nil)
        let draggingItems: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(
                CGRect(
                    x: location.x + CGFloat(index) * 6 - 16,
                    y: location.y - 16,
                    width: 32,
                    height: 32
                ),
                contents: icon
            )
            return item
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
        onDragStarted?()
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

struct MultiDragView: NSViewRepresentable {
    let urls: [URL]
    var onDragStarted: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil

    func makeNSView(context _: Context) -> NSView {
        let view = MultiDragNSView()
        view.urls = urls
        view.onDragStarted = onDragStarted
        view.onTap = onTap
        view.onDoubleTap = onDoubleTap
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? MultiDragNSView else { return }
        view.urls = urls
        view.onDragStarted = onDragStarted
        view.onTap = onTap
        view.onDoubleTap = onDoubleTap
    }
}
