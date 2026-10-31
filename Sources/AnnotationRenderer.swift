import AppKit

/// Headless compositing of annotations onto a source image (shared by the editor's export and
/// by the `--selftest` CLI, which verifies every tool's rendering without any GUI interaction).
enum AnnotationRenderer {
    static func render(source: CGImage, captureScale: CGFloat, annotations: [Annotation]) -> NSImage {
        let pointSize = NSSize(width: CGFloat(source.width) / captureScale,
                               height: CGFloat(source.height) / captureScale)
        let img = NSImage(size: pointSize)
        img.lockFocusFlipped(true)
        NSImage(cgImage: source, size: pointSize).draw(in: NSRect(origin: .zero, size: pointSize))
        for a in annotations {
            a.draw(v: { $0 }, zoom: 1, source: source, captureScale: captureScale)
        }
        img.unlockFocus()
        return img
    }

    static func png(source: CGImage, captureScale: CGFloat, annotations: [Annotation]) -> Data? {
        let img = render(source: source, captureScale: captureScale, annotations: annotations)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        rep.size = NSSize(width: CGFloat(source.width) / captureScale, height: CGFloat(source.height) / captureScale)
        return rep.representation(using: .png, properties: [:])
    }

    /// One of every annotation kind, laid out across an image of the given point size.
    static func demoAnnotations(pointSize: NSSize) -> [Annotation] {
        let W = pointSize.width, H = pointSize.height
        func A(_ kind: Annotation.Kind, _ sx: CGFloat, _ sy: CGFloat, _ ex: CGFloat, _ ey: CGFloat,
               color: NSColor = .systemRed, width: CGFloat = 4) -> Annotation {
            Annotation(kind: kind, color: color, lineWidth: width,
                       start: CGPoint(x: sx * W, y: sy * H), end: CGPoint(x: ex * W, y: ey * H))
        }
        var out: [Annotation] = []
        out.append(A(.rectangle, 0.05, 0.10, 0.30, 0.30))
        out.append(A(.roundedRect, 0.35, 0.10, 0.60, 0.30, color: .systemOrange))
        out.append(A(.ellipse, 0.65, 0.10, 0.92, 0.30, color: .systemYellow))
        out.append(A(.arrow, 0.05, 0.45, 0.28, 0.60, color: .systemGreen))
        out.append(A(.line, 0.35, 0.45, 0.60, 0.60, color: .systemBlue))
        out.append(A(.highlight, 0.65, 0.44, 0.92, 0.52, color: .systemYellow))
        out.append(A(.blur, 0.05, 0.68, 0.30, 0.90))
        out.append(A(.pixelate, 0.35, 0.68, 0.60, 0.90))

        let pen = A(.pen, 0.65, 0.70, 0.92, 0.88, color: .systemPink, width: 5)
        var pts: [CGPoint] = []
        for i in 0...20 {
            let t = CGFloat(i) / 20
            pts.append(CGPoint(x: (0.65 + 0.27 * t) * W, y: (0.80 + 0.08 * sin(t * .pi * 3)) * H))
        }
        pen.points = pts
        out.append(pen)

        let c1 = A(.counter, 0.16, 0.40, 0.16, 0.40, color: .systemRed); c1.number = 1; c1.fontSize = 20
        let c2 = A(.counter, 0.46, 0.40, 0.46, 0.40, color: .systemRed); c2.number = 2; c2.fontSize = 20
        out.append(c1); out.append(c2)

        let text = A(.text, 0.05, 0.36, 0.05, 0.36, color: .white)
        text.text = "Screenshots"; text.fontSize = 28
        out.append(text)
        return out
    }
}
