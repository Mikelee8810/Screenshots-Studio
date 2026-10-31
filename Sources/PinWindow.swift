import AppKit
import Carbon.HIToolbox

/// Floating always-on-top screenshot ("pin to screen"). Draggable, with a right-click menu.
@MainActor
final class PinController {
    static let shared = PinController()
    private var windows: [NSWindow] = []
    private init() {}

    func pin(_ image: NSImage, at originPoint: CGPoint?) {
        let size = image.size
        let frame: NSRect
        if let o = originPoint {
            frame = Coordinates.appKitRect(fromCGTopLeft: CGRect(origin: o, size: size))
        } else {
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            frame = NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height)
        }
        let win = PinWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinImageView(frame: NSRect(origin: .zero, size: size), image: image)
        view.onClose = { [weak self, weak win] in
            guard let win = win else { return }
            win.orderOut(nil)
            self?.windows.removeAll { $0 === win }
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        windows.append(win)
    }
}

final class PinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class PinImageView: NSView {
    private let image: NSImage
    var onClose: (() -> Void)?

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        layer?.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
    }

    override func keyDown(with e: NSEvent) {
        if Int(e.keyCode) == kVK_Escape { onClose?() } else { super.keyDown(with: e) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "c").target = self
        m.addItem(withTitle: "Save…", action: #selector(saveImage), keyEquivalent: "s").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "w").target = self
        return m
    }

    @objc private func copyImage() {
        let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([image])
        HUD.show("Copied to clipboard")
    }
    @objc private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Pinned.png"
        if panel.runModal() == .OK, let url = panel.url,
           let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
    @objc private func closePin() { onClose?() }
}
