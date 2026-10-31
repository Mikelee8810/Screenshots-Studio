import AppKit
import CoreImage

/// One editable mark on the canvas. All geometry is stored in IMAGE point space
/// (top-left origin, y-down) so it is independent of zoom/pan. Reference type so the
/// editor can mutate in place and cache expensive renders; undo works on deep copies.
final class Annotation {
    enum Kind {
        case arrow, line, rectangle, roundedRect, ellipse, highlight, pen, counter, text, blur, pixelate
    }

    let id = UUID()
    var kind: Kind
    var color: NSColor
    var lineWidth: CGFloat
    var start: CGPoint          // image space
    var end: CGPoint            // image space
    var points: [CGPoint] = []  // pen path (image space)
    var text: String = ""
    var number: Int = 1
    var fontSize: CGFloat = 20

    // cache for blur/pixelate
    private var cachedProcessed: CGImage?
    private var cachedKey: String = ""

    init(kind: Kind, color: NSColor, lineWidth: CGFloat, start: CGPoint, end: CGPoint) {
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
        self.start = start
        self.end = end
    }

    func copy() -> Annotation {
        let a = Annotation(kind: kind, color: color, lineWidth: lineWidth, start: start, end: end)
        a.points = points
        a.text = text
        a.number = number
        a.fontSize = fontSize
        return a
    }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Bounding box in image space (for selection + hit tests).
    var boundingBox: CGRect {
        switch kind {
        case .counter:
            let r = fontSize
            return CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)
        case .text:
            let size = (text.isEmpty ? "Text" : text as NSString).size(withAttributes: textAttributes(scale: 1))
            return CGRect(x: start.x, y: start.y, width: max(size.width, 20), height: max(size.height, fontSize))
        case .pen:
            guard let first = points.first else { return .zero }
            var box = CGRect(origin: first, size: .zero)
            for p in points { box = box.union(CGRect(origin: p, size: .zero)) }
            return box.insetBy(dx: -lineWidth, dy: -lineWidth)
        default:
            return rect.insetBy(dx: -max(6, lineWidth), dy: -max(6, lineWidth))
        }
    }

    // MARK: Handles (image space)

    /// Resize handle positions. Empty = move-only.
    func handlePositions() -> [CGPoint] {
        switch kind {
        case .arrow, .line:
            return [start, end]
        case .rectangle, .roundedRect, .ellipse, .highlight, .blur, .pixelate:
            let r = rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        case .counter, .text, .pen:
            return []
        }
    }

    func resize(handleIndex i: Int, to p: CGPoint) {
        switch kind {
        case .arrow, .line:
            if i == 0 { start = p } else { end = p }
        case .rectangle, .roundedRect, .ellipse, .highlight, .blur, .pixelate:
            let r = rect
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                           CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            let fixed = corners[(i + 2) % 4] // diagonally opposite corner stays put
            start = fixed
            end = p
            invalidateCache()
        default:
            break
        }
    }

    /// Resize a rectangular shape keeping a fixed anchor corner. The anchor must be captured
    /// once at drag start (not re-derived each tick) so the shape can be flipped through a corner
    /// without collapsing.
    func resizeRect(anchor: CGPoint, corner: CGPoint) {
        start = anchor
        end = corner
        invalidateCache()
    }

    func translate(by d: CGVector) {
        start.x += d.dx; start.y += d.dy
        end.x += d.dx; end.y += d.dy
        for k in points.indices { points[k].x += d.dx; points[k].y += d.dy }
        invalidateCache()
    }

    // MARK: Hit testing (image space)

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .arrow, .line:
            return distanceToSegment(p, start, end) <= max(tolerance, lineWidth)
        case .pen:
            for i in 1..<max(points.count, 1) where i < points.count {
                if distanceToSegment(p, points[i - 1], points[i]) <= max(tolerance, lineWidth) { return true }
            }
            return false
        case .rectangle, .roundedRect, .ellipse:
            // near the stroke or inside
            return boundingBox.contains(p)
        default:
            return boundingBox.contains(p)
        }
    }

    // MARK: Drawing

    /// Draw into the current (flipped) graphics context. `v` maps image→view points; `zoom`
    /// scales line widths; `source`/`captureScale` feed blur/pixelate.
    func draw(v: (CGPoint) -> CGPoint, zoom: CGFloat, source: CGImage?, captureScale: CGFloat) {
        let w = max(0.5, lineWidth * zoom)
        color.setStroke()
        color.setFill()

        switch kind {
        case .line:
            strokePath([start, end], v: v, width: w, cap: .round)
        case .arrow:
            drawArrow(v: v, width: w)
        case .rectangle:
            let p = NSBezierPath(rect: viewRect(v)); p.lineWidth = w; p.stroke()
        case .roundedRect:
            let radius = min(viewRect(v).width, viewRect(v).height) * 0.18
            let p = NSBezierPath(roundedRect: viewRect(v), xRadius: radius, yRadius: radius); p.lineWidth = w; p.stroke()
        case .ellipse:
            let p = NSBezierPath(ovalIn: viewRect(v)); p.lineWidth = w; p.stroke()
        case .highlight:
            let hp = NSBezierPath(rect: viewRect(v))
            color.withAlphaComponent(0.28).setFill()
            NSGraphicsContext.current?.compositingOperation = .multiply
            hp.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        case .pen:
            strokePath(points, v: v, width: w, cap: .round)
        case .counter:
            drawCounter(v: v, zoom: zoom)
        case .text:
            drawText(v: v, zoom: zoom)
        case .blur, .pixelate:
            drawProcessed(v: v, source: source, captureScale: captureScale)
        }
    }

    private func viewRect(_ v: (CGPoint) -> CGPoint) -> CGRect {
        let a = v(CGPoint(x: rect.minX, y: rect.minY))
        let b = v(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func strokePath(_ pts: [CGPoint], v: (CGPoint) -> CGPoint, width: CGFloat, cap: NSBezierPath.LineCapStyle) {
        guard pts.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = cap
        path.lineJoinStyle = .round
        path.move(to: v(pts[0]))
        for p in pts.dropFirst() { path.line(to: v(p)) }
        path.stroke()
    }

    private func drawArrow(v: (CGPoint) -> CGPoint, width: CGFloat) {
        let s = v(start), e = v(end)
        let angle = atan2(e.y - s.y, e.x - s.x)
        let headLen = max(10, width * 3.2)
        let headWidth = max(8, width * 2.6)
        // shaft stops a bit short so the head is clean
        let shaftEnd = CGPoint(x: e.x - cos(angle) * headLen * 0.6, y: e.y - sin(angle) * headLen * 0.6)
        let shaft = NSBezierPath()
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.move(to: s); shaft.line(to: shaftEnd); shaft.stroke()
        let left = CGPoint(x: e.x - cos(angle - .pi / 7) * headLen, y: e.y - sin(angle - .pi / 7) * headLen)
        let right = CGPoint(x: e.x - cos(angle + .pi / 7) * headLen, y: e.y - sin(angle + .pi / 7) * headLen)
        let head = NSBezierPath()
        head.move(to: e); head.line(to: left); head.line(to: right); head.close()
        head.fill()
        _ = headWidth
    }

    private func drawCounter(v: (CGPoint) -> CGPoint, zoom: CGFloat) {
        let c = v(start)
        let r = fontSize * zoom
        let circle = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        color.setFill(); circle.fill()
        NSColor.white.setStroke(); circle.lineWidth = max(1, zoom); circle.stroke()
        let s = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: r * 1.1, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let sz = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2), withAttributes: attrs)
    }

    private func textAttributes(scale: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize * scale, weight: .semibold),
         .foregroundColor: color]
    }

    private func drawText(v: (CGPoint) -> CGPoint, zoom: CGFloat) {
        let origin = v(start)
        let s = (text.isEmpty ? " " : text) as NSString
        s.draw(at: origin, withAttributes: textAttributes(scale: zoom))
    }

    private func drawProcessed(v: (CGPoint) -> CGPoint, source: CGImage?, captureScale: CGFloat) {
        let vr = viewRect(v)
        guard let processed = processedImage(source: source, captureScale: captureScale) else {
            NSColor.black.withAlphaComponent(0.25).setFill(); NSBezierPath(rect: vr).fill(); return
        }
        NSGraphicsContext.current?.imageInterpolation = kind == .pixelate ? .none : .default
        NSImage(cgImage: processed, size: vr.size).draw(in: vr, from: .zero, operation: .copy, fraction: 1)
    }

    private func invalidateCache() { cachedProcessed = nil; cachedKey = "" }

    private func processedImage(source: CGImage?, captureScale: CGFloat) -> CGImage? {
        guard let source = source else { return nil }
        let r = rect
        guard r.width >= 1, r.height >= 1 else { return nil }
        let key = "\(kind)-\(Int(r.minX))-\(Int(r.minY))-\(Int(r.width))-\(Int(r.height))"
        if key == cachedKey, let c = cachedProcessed { return c }

        let px = CGRect(x: r.minX * captureScale, y: r.minY * captureScale,
                        width: r.width * captureScale, height: r.height * captureScale).integral
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let clamped = px.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let sub = source.cropping(to: clamped) else { return nil }

        let ci = CIImage(cgImage: sub)
        let out: CIImage
        if kind == .blur {
            let sigma = max(4, min(clamped.width, clamped.height) / 12)
            out = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: ci.extent)
        } else {
            let f = CIFilter(name: "CIPixellate")!
            f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            let cell = max(6, min(clamped.width, clamped.height) / 14)
            f.setValue(cell, forKey: "inputScale")
            f.setValue(CIVector(x: clamped.midX, y: clamped.midY), forKey: "inputCenter")
            out = (f.outputImage ?? ci).cropped(to: ci.extent)
        }
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(out, from: ci.extent) else { return nil }
        cachedProcessed = cg; cachedKey = key
        return cg
    }
}

private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    if dx == 0 && dy == 0 { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
    let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    return hypot(p.x - proj.x, p.y - proj.y)
}
