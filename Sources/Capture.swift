import Foundation
import ScreenCaptureKit
import AppKit
import CoreMedia

/// Errors surfaced by the capture layer.
enum CaptureError: Error, LocalizedError {
    case noDisplay
    case noPermission
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available to capture."
        case .noPermission: return "Screen Recording permission is required. Grant it in System Settings ▸ Privacy & Security ▸ Screen Recording."
        case .failed(let m): return m
        }
    }
}

/// Low-level screen capture built on ScreenCaptureKit (the only supported path on macOS 15+,
/// since CGDisplayCreateImage was removed).
enum ScreenCapture {

    static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // ScreenCaptureKit reports a permission failure as an error here.
            throw CaptureError.noPermission
        }
    }

    /// Backing scale factor for a given ScreenCaptureKit display (matches it to an NSScreen).
    /// @MainActor because it reads NSScreen (AppKit, main-thread only).
    @MainActor
    static func scale(for display: SCDisplay) -> CGFloat {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == display.displayID {
                return screen.backingScaleFactor
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    /// The NSScreen corresponding to a ScreenCaptureKit display.
    @MainActor
    static func nsScreen(for display: SCDisplay) -> NSScreen? {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == display.displayID {
                return screen
            }
        }
        return NSScreen.main
    }

    /// Capture a full display at native pixel resolution.
    @MainActor
    static func captureDisplay(_ display: SCDisplay) async throws -> CGImage {
        let s = scale(for: display)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = Int(CGFloat(display.width) * s)
        cfg.height = Int(CGFloat(display.height) * s)
        cfg.showsCursor = false
        cfg.capturesAudio = false
        cfg.scalesToFit = false
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            throw CaptureError.failed("Display capture failed: \(error.localizedDescription)")
        }
    }

    /// Capture a single window (image is cropped to the window, transparent outside its shape).
    @MainActor
    static func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let s = displayScale(containing: window)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(window.frame.width * s))
        cfg.height = max(1, Int(window.frame.height * s))
        cfg.showsCursor = false
        cfg.capturesAudio = false
        // Exclude the shadow so the captured content matches window.frame exactly (keeps the
        // pixel size and the pin-back origin correct).
        cfg.ignoreShadowsSingleWindow = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            throw CaptureError.failed("Window capture failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func displayScaleForWindowPublic(_ window: SCWindow) -> CGFloat { displayScale(containing: window) }

    @MainActor
    private static func displayScale(containing window: SCWindow) -> CGFloat {
        // Use the backing scale of the display containing the window's CENTER (in CG top-left space),
        // reusing the correct multi-display containment helper.
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        if let screen = Coordinates.screen(forCGTopLeft: center) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    /// Crop a captured display image (native pixels) using a rect expressed in that display's
    /// point coordinates (top-left origin).
    static func crop(_ image: CGImage, toPointRect rect: CGRect, scale: CGFloat) -> CGImage? {
        let px = CGRect(x: rect.origin.x * scale,
                        y: rect.origin.y * scale,
                        width: rect.size.width * scale,
                        height: rect.size.height * scale).integral
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = px.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return image.cropping(to: clamped)
    }

    /// Build an NSImage sized in points (so it draws 1:1 on a Retina display) from a pixel CGImage.
    static func nsImage(from cg: CGImage, scale: CGFloat) -> NSImage {
        let pointSize = NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        let img = NSImage(cgImage: cg, size: pointSize)
        return img
    }
}
