import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

/// Drives "capture a window": dims the screen and highlights whichever window is under the cursor;
/// a click captures just that window (crisp, shadow included).
@MainActor
final class WindowPickerController {
    static let shared = WindowPickerController()

    private var windows: [OverlayWindow] = []
    private var frozens: [FrozenScreen] = []
    private var candidates: [SCWindow] = []
    private(set) var hovered: SCWindow?
    private var completion: ((CapturedImage?) -> Void)?
    private var finished = false

    var isActive: Bool { !windows.isEmpty }

    func begin(completion: @escaping (CapturedImage?) -> Void) {
        guard !isActive else { return }
        self.completion = completion
        self.finished = false
        Task { @MainActor in
            do {
                let content = try await ScreenCapture.shareableContent()
                let frozens = try await ScreenFreezer.freezeAll()
                self.frozens = frozens
                let myPID = ProcessInfo.processInfo.processIdentifier
                candidates = content.windows.filter { w in
                    w.isOnScreen && w.frame.width > 40 && w.frame.height > 40 &&
                    w.windowLayer == 0 &&
                    w.owningApplication?.processID != pid_t(myPID)
                }
                NSApp.activate(ignoringOtherApps: true)
                let mouse = NSEvent.mouseLocation
                for f in frozens {
                    let win = OverlayWindow(screenFrame: f.screen.frame)
                    let view = WindowPickerView(frozen: f)
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

    /// A view reports the cursor at a CG global top-left point; find the frontmost window under it.
    func updateHover(cgPoint: CGPoint) {
        let newHover = candidates.first { $0.frame.contains(cgPoint) }
        if newHover?.windowID != hovered?.windowID {
            hovered = newHover
            for w in windows { w.contentView?.needsDisplay = true }
        }
    }

    func pickHovered() {
        guard let target = hovered, !finished else { cancel(); return }
        finished = true
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        Task { @MainActor in
            do {
                let cg = try await ScreenCapture.captureWindow(target)
                let scale = ScreenCapture.displayScaleForWindowPublic(target)
                let origin = CGPoint(x: target.frame.minX, y: target.frame.minY)
                let captured = CapturedImage(cgImage: cg, scale: scale, originPoint: origin)
                deliver(captured)
            } catch {
                deliver(nil)
                CaptureController.shared.present(error: error)
            }
        }
    }

    func cancel() { finish(nil) }

    private func finish(_ result: CapturedImage?) {
        guard !finished else { return }
        finished = true
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        deliver(result)
    }

    private func deliver(_ result: CapturedImage?) {
        frozens.removeAll()
        candidates.removeAll()
        hovered = nil
        let c = completion; completion = nil
        c?(result)
    }
}

final class WindowPickerView: NSView {
    weak var controller: WindowPickerController?
    private let frozen: FrozenScreen
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
        guard let w = window else { return }
        let vp = convert(w.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let origin = Coordinates.cgOrigin(of: frozen.screen)
        controller?.updateHover(cgPoint: CGPoint(x: origin.x + vp.x, y: origin.y + vp.y))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }

    private func cgPoint(from e: NSEvent) -> CGPoint {
        let vp = convert(e.locationInWindow, from: nil)         // flipped, screen-local, top-left
        let origin = Coordinates.cgOrigin(of: frozen.screen)
        return CGPoint(x: origin.x + vp.x, y: origin.y + vp.y)
    }

    override func mouseMoved(with e: NSEvent) {
        NSCursor.pointingHand.set()
        controller?.updateHover(cgPoint: cgPoint(from: e))
    }
    override func mouseDown(with e: NSEvent) {
        controller?.updateHover(cgPoint: cgPoint(from: e))
        controller?.pickHovered()
    }
    override func keyDown(with e: NSEvent) {
        if Int(e.keyCode) == kVK_Escape { controller?.cancel() }
    }

    /// Rect (this screen's flipped view coords) for a global CG window frame, if it intersects.
    private func viewRect(for windowFrame: CGRect) -> CGRect? {
        let origin = Coordinates.cgOrigin(of: frozen.screen)
        let local = CGRect(x: windowFrame.minX - origin.x, y: windowFrame.minY - origin.y,
                           width: windowFrame.width, height: windowFrame.height)
        return local.intersects(bounds) ? local : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        frozen.nsImage.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        guard let hovered = controller?.hovered, let r = viewRect(for: hovered.frame) else { return }
        ctx.saveGraphicsState()
        NSBezierPath(rect: r).setClip()
        frozen.nsImage.draw(in: bounds)
        ctx.restoreGraphicsState()

        NSColor.systemBlue.withAlphaComponent(0.15).setFill()
        NSBezierPath(rect: r).fill()
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: r); border.lineWidth = 2; border.stroke()

        let name = hovered.owningApplication?.applicationName ?? "Window"
        let caption = "\(name)  ·  \(Int(hovered.frame.width)) × \(Int(hovered.frame.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let cs = (caption as NSString).size(withAttributes: attrs)
        let capRect = CGRect(x: r.midX - (cs.width + 16) / 2, y: max(6, r.minY - 30),
                             width: cs.width + 16, height: 24)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: capRect, xRadius: 6, yRadius: 6).fill()
        (caption as NSString).draw(at: CGPoint(x: capRect.minX + 8, y: capRect.minY + 5), withAttributes: attrs)
    }
}
