import AppKit
import ScreenCaptureKit

/// A borderless full-screen window that can become key (so it receives Esc / key events).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
    }
}

/// A frozen snapshot of one physical screen, used as the backdrop for selection overlays.
struct FrozenScreen {
    let screen: NSScreen
    let display: SCDisplay
    let cgImage: CGImage
    let nsImage: NSImage
    let bitmap: NSBitmapImageRep   // for fast pixel colour sampling
    let scale: CGFloat

    /// Colour of the pixel at a point expressed in the (flipped, top-left) overlay-view space.
    func color(atViewPoint p: CGPoint) -> NSColor {
        let x = Int((p.x * scale).rounded())
        let y = Int((p.y * scale).rounded())
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return .black }
        return bitmap.colorAt(x: x, y: y) ?? .black
    }
}

enum ScreenFreezer {
    /// Capture every screen at native resolution. Ordered to match NSScreen.screens.
    /// @MainActor because it reads NSScreen and calls the main-actor capture helpers.
    @MainActor
    static func freezeAll() async throws -> [FrozenScreen] {
        let content = try await ScreenCapture.shareableContent()
        var out: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == CGDirectDisplayID(num.uint32Value) })
            else { continue }
            let cg = try await ScreenCapture.captureDisplay(display)
            let scale = ScreenCapture.scale(for: display)
            let ns = ScreenCapture.nsImage(from: cg, scale: scale)
            guard let bitmap = NSBitmapImageRep(cgImage: cg) as NSBitmapImageRep? else { continue }
            out.append(FrozenScreen(screen: screen, display: display, cgImage: cg,
                                    nsImage: ns, bitmap: bitmap, scale: scale))
        }
        if out.isEmpty { throw CaptureError.noDisplay }
        return out
    }
}
