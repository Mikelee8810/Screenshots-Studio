import AppKit

/// A finished capture: the native-pixel image plus the scale needed to present it in points,
/// and (optionally) the global top-left point where it came from — used to pin it back in place.
struct CapturedImage {
    let cgImage: CGImage
    let scale: CGFloat
    var originPoint: CGPoint?   // global, top-left origin, points

    var pixelSize: NSSize { NSSize(width: cgImage.width, height: cgImage.height) }
    var pointSize: NSSize { NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale) }

    var nsImage: NSImage { ScreenCapture.nsImage(from: cgImage, scale: scale) }

    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize
        return rep.representation(using: .png, properties: [:])
    }
}
