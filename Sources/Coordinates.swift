import AppKit

/// Conversions between AppKit global coordinates (origin bottom-left of the primary screen, y-up)
/// and CoreGraphics "global top-left" coordinates (origin top-left of the primary screen, y-down),
/// which is what SCWindow.frame and CGEvent locations use.
enum Coordinates {
    /// Height of the primary screen (the one whose AppKit origin is (0,0)).
    static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
    }

    /// CG global top-left origin of a screen's top-left corner.
    static func cgOrigin(of screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
    }

    /// AppKit rect (y-up) from a CG global top-left rect (y-down).
    static func appKitRect(fromCGTopLeft r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// CG global top-left rect (y-down) from an AppKit rect (y-up).
    static func cgTopLeftRect(fromAppKit r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The screen containing a CG global top-left point, if any.
    static func screen(forCGTopLeft p: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            let origin = cgOrigin(of: screen)
            let rect = CGRect(origin: origin, size: screen.frame.size)
            if rect.contains(p) { return screen }
        }
        return nil
    }
}

extension NSColor {
    /// Uppercase hex string like "#1A2B3C" in sRGB.
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
