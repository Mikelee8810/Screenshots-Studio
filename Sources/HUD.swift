import AppKit

/// A small transient toast shown near the top of the active screen (e.g. "Copied to clipboard").
@MainActor
enum HUD {
    private static var window: NSWindow?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String) {
        hideWork?.cancel()
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let pad = NSSize(width: 28, height: 16)
        let size = NSSize(width: label.frame.width + pad.width * 2, height: label.frame.height + pad.height)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - 120
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)

        let win = window ?? {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window = w
            return w
        }()
        win.setFrame(frame, display: true)

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        label.frame.origin = CGPoint(x: pad.width, y: (size.height - label.frame.height) / 2)
        bg.addSubview(label)
        win.contentView = bg
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 1
        }

        let targetWin = win
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                targetWin.animator().alphaValue = 0
            }, completionHandler: {
                targetWin.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}
