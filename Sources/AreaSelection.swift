import AppKit
import Carbon.HIToolbox

/// Drives interactive "select an area" capture: freezes every screen, shows a dimmed overlay
/// with a drag-to-select rectangle, live dimensions, a crosshair guide, and a magnifier loupe
/// (zoomed pixels + hex colour) — the Shottr feel.
@MainActor
final class AreaSelectionController {
    static let shared = AreaSelectionController()

    private var windows: [OverlayWindow] = []
    private var completion: ((CapturedImage?) -> Void)?
    private var finished = false

    var isActive: Bool { !windows.isEmpty }

    func begin(completion: @escaping (CapturedImage?) -> Void) {
        guard !isActive else { return }
        self.completion = completion
        self.finished = false
        Task { @MainActor in
            do {
                let frozens = try await ScreenFreezer.freezeAll()
                NSApp.activate(ignoringOtherApps: true)
                let mouse = NSEvent.mouseLocation
                for f in frozens {
                    let win = OverlayWindow(screenFrame: f.screen.frame)
                    let view = AreaOverlayView(frozen: f)
                    view.controller = self
                    win.contentView = view
                    win.orderFrontRegardless()
                    if NSMouseInRect(mouse, f.screen.frame, false) { win.makeKey() }
                    windows.append(win)
                }
                if !windows.contains(where: { $0.isKeyWindow }) { windows.first?.makeKey() }
            } catch {
                self.finish(nil)
                CaptureController.shared.present(error: error)
            }
        }
    }

    func cancel() { finish(nil) }

    /// Called by a view when the user finishes a drag. `rect` is in that screen's flipped view points.
    func complete(rect: CGRect, in frozen: FrozenScreen) {
        guard !finished else { return }
        guard rect.width >= 2, rect.height >= 2,
              let cropped = ScreenCapture.crop(frozen.cgImage, toPointRect: rect, scale: frozen.scale) else {
            finish(nil); return
        }
        let cgOrigin = Coordinates.cgOrigin(of: frozen.screen)
        let originPoint = CGPoint(x: cgOrigin.x + rect.origin.x, y: cgOrigin.y + rect.origin.y)
        Config.shared.fixedRect = CGRect(origin: originPoint, size: rect.size) // remember for "fixed region"
        finish(CapturedImage(cgImage: cropped, scale: frozen.scale, originPoint: originPoint))
    }

    private func finish(_ result: CapturedImage?) {
        guard !finished else { return }
        finished = true
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        let c = completion; completion = nil
        c?(result)
    }
}

final class AreaOverlayView: NSView {
    weak var controller: AreaSelectionController?
    private let frozen: FrozenScreen

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var mousePoint: CGPoint = .zero
    private var dragging = false
    private var trackingArea: NSTrackingArea?

    init(frozen: FrozenScreen) {
        self.frozen = frozen
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window {
            let inWin = w.convertPoint(fromScreen: NSEvent.mouseLocation)
            mousePoint = convert(inWin, from: nil)
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private var selectionRect: CGRect? {
        guard let s = startPoint, let c = currentPoint else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        startPoint = p; currentPoint = p; mousePoint = p; dragging = true
        needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        currentPoint = p; mousePoint = p
        needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        dragging = false
        if let r = selectionRect, r.width >= 2, r.height >= 2 {
            controller?.complete(rect: r, in: frozen)
        } else {
            controller?.cancel()
        }
    }
    override func mouseMoved(with e: NSEvent) {
        mousePoint = convert(e.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }
    override func mouseEntered(with e: NSEvent) { NSCursor.crosshair.set() }
    override func mouseExited(with e: NSEvent) { NSCursor.arrow.set() }

    override func keyDown(with e: NSEvent) {
        if Int(e.keyCode) == kVK_Escape { controller?.cancel() }
        else if Int(e.keyCode) == kVK_Return, let r = selectionRect, r.width >= 2 {
            controller?.complete(rect: r, in: frozen)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        frozen.nsImage.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()

        let sel = selectionRect
        if let sel = sel, sel.width > 0, sel.height > 0 {
            ctx.saveGraphicsState()
            NSBezierPath(rect: sel).setClip()
            frozen.nsImage.draw(in: bounds)
            ctx.restoreGraphicsState()

            NSColor.white.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1.5
            border.stroke()
            drawDimensions(for: sel)
        } else {
            // Full-screen crosshair guide before dragging.
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let h = NSBezierPath(); h.move(to: CGPoint(x: 0, y: mousePoint.y)); h.line(to: CGPoint(x: bounds.width, y: mousePoint.y))
            let v = NSBezierPath(); v.move(to: CGPoint(x: mousePoint.x, y: 0)); v.line(to: CGPoint(x: mousePoint.x, y: bounds.height))
            h.lineWidth = 1; v.lineWidth = 1; h.stroke(); v.stroke()
        }

        drawMagnifier(at: mousePoint)
    }

    private func drawDimensions(for sel: CGRect) {
        let text = "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        var labelRect = CGRect(x: sel.minX, y: sel.maxY + 6, width: size.width + pad * 2, height: size.height + 4)
        if labelRect.maxY > bounds.height - 4 { labelRect.origin.y = sel.minY - labelRect.height - 6 }
        if labelRect.maxX > bounds.width { labelRect.origin.x = bounds.width - labelRect.width - 2 }
        labelRect.origin.x = max(2, labelRect.origin.x)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: labelRect.minX + pad, y: labelRect.minY + 2), withAttributes: attrs)
    }

    private func drawMagnifier(at p: CGPoint) {
        let zoom: CGFloat = 8
        let loupe: CGFloat = 132
        // Position loupe near cursor, offset so it doesn't sit under the pointer.
        var origin = CGPoint(x: p.x + 18, y: p.y + 18)
        if origin.x + loupe > bounds.width { origin.x = p.x - loupe - 18 }
        if origin.y + loupe > bounds.height { origin.y = p.y - loupe - 18 }
        origin.x = max(4, origin.x); origin.y = max(4, origin.y)
        let dest = CGRect(origin: origin, size: CGSize(width: loupe, height: loupe))

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()

        // Source pixel region around cursor.
        let srcPts = loupe / zoom
        let srcPx = srcPts * frozen.scale
        let cx = p.x * frozen.scale, cy = p.y * frozen.scale
        let srcRect = CGRect(x: cx - srcPx / 2, y: cy - srcPx / 2, width: srcPx, height: srcPx).integral

        let clip = NSBezierPath(roundedRect: dest, xRadius: 8, yRadius: 8)
        clip.setClip()
        NSColor.black.setFill(); dest.fill()
        if let sub = frozen.cgImage.cropping(to: srcRect.intersection(CGRect(x: 0, y: 0, width: frozen.cgImage.width, height: frozen.cgImage.height))) {
            ctx.imageInterpolation = .none
            NSImage(cgImage: sub, size: dest.size).draw(in: dest, from: .zero, operation: .copy, fraction: 1)
        }
        // Crosshair inside loupe (center cell).
        let cell = zoom
        let center = CGPoint(x: dest.midX, y: dest.midY)
        NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
        let cross = NSBezierPath(rect: CGRect(x: center.x - cell / 2, y: center.y - cell / 2, width: cell, height: cell))
        cross.lineWidth = 1; cross.stroke()
        ctx.restoreGraphicsState()

        // Border + caption.
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(roundedRect: dest, xRadius: 8, yRadius: 8); ring.lineWidth = 1; ring.stroke()

        let color = frozen.color(atViewPoint: p)
        let caption = "\(Int(p.x)), \(Int(p.y))   \(color.hexString)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let cs = (caption as NSString).size(withAttributes: attrs)
        let capRect = CGRect(x: dest.minX, y: dest.maxY + 3, width: max(loupe, cs.width + 12), height: cs.height + 6)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: capRect, xRadius: 4, yRadius: 4).fill()
        // colour swatch
        let sw = CGRect(x: capRect.minX + 5, y: capRect.midY - 5, width: 10, height: 10)
        color.setFill(); NSBezierPath(rect: sw).fill()
        NSColor.white.withAlphaComponent(0.5).setStroke(); NSBezierPath(rect: sw).stroke()
        (caption as NSString).draw(at: CGPoint(x: capRect.minX + 20, y: capRect.minY + 3), withAttributes: attrs)
    }
}
