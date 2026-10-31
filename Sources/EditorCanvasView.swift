import AppKit
import Carbon.HIToolbox

/// Snapshot of everything the undo stack must restore.
private struct EditorState {
    var annotations: [Annotation]
    var source: CGImage
    var scale: CGFloat
    var counterValue: Int
}

/// The annotation canvas: checkerboard + image + marks, with per-tool mouse handling,
/// selection/move/resize, undo/redo, zoom, text editing, and crop. Lives inside an NSScrollView;
/// its frame is imagePointSize * zoom, so the scroll view provides pan/scrollbars.
@MainActor
final class EditorCanvasView: NSView {

    // Model
    private(set) var source: CGImage
    private(set) var captureScale: CGFloat   // image points -> source pixels
    private(set) var annotations: [Annotation] = []
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []

    // Tool state
    var tool: Tool = .arrow { didSet { if tool != .select { deselect() }; window?.invalidateCursorRects(for: self) } }
    var strokeColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var counterValue: Int = 1

    // View state
    private(set) var zoom: CGFloat = 1
    private var selected: Annotation?
    private var draft: Annotation?          // shape being dragged out
    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint = .zero  // image space
    private var activeHandle: Int = -1
    private var resizeAnchor: CGPoint = .zero // fixed corner captured at drag start (rect-like resize)
    private var resizingRect = false
    private var pendingUndo = false           // push an undo snapshot on the first real drag delta
    private var textSnapshotPending = false    // a freshly-created text has an unresolved undo snapshot
    private var textEditor: NSTextView?
    private var editingAnnotation: Annotation?

    // Callbacks to the window chrome
    var onStateChange: (() -> Void)?
    var onHover: ((NSColor, CGPoint) -> Void)?
    var onToolChange: ((Tool) -> Void)?

    private var hoverTracking: NSTrackingArea?

    private enum DragMode { case none, creating, moving, resizing }

    init(captured: CapturedImage) {
        self.source = captured.cgImage
        self.captureScale = captured.scale
        super.init(frame: NSRect(origin: .zero, size: captured.pointSize))
        wantsLayer = true
        setZoom(1)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override var isOpaque: Bool { false }

    var imagePointSize: NSSize { NSSize(width: CGFloat(source.width) / captureScale, height: CGFloat(source.height) / captureScale) }

    // MARK: Zoom

    func setZoom(_ z: CGFloat) {
        zoom = max(0.1, min(8, z))
        setFrameSize(NSSize(width: imagePointSize.width * zoom, height: imagePointSize.height * zoom))
        needsDisplay = true
        onStateChange?()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); hoverTracking = t
    }

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func zoomActual() { setZoom(1) }
    func zoomToFit() {
        guard let cv = enclosingScrollView?.contentView else { setZoom(1); return }
        let s = min(cv.bounds.width / imagePointSize.width, cv.bounds.height / imagePointSize.height)
        setZoom(min(1, s))
    }

    // MARK: Coordinate conversion

    /// Event location -> image point space.
    private func imagePoint(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: p.x / zoom, y: p.y / zoom)
    }
    /// image point -> view point
    private func vp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom, y: p.y * zoom) }

    // MARK: Undo

    private func snapshot() -> EditorState {
        EditorState(annotations: annotations.map { $0.copy() }, source: source, scale: captureScale, counterValue: counterValue)
    }
    private func pushUndo() {
        undoStack.append(snapshot())
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        apply(s)
    }
    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        apply(s)
    }
    private func apply(_ s: EditorState) {
        annotations = s.annotations
        source = s.source
        captureScale = s.scale
        counterValue = s.counterValue
        cachedRep = nil               // the pixel-sampling cache belongs to the old source
        selected = nil
        endTextEditing(commit: false)
        setZoom(zoom)
        needsDisplay = true
        onStateChange?()
    }

    // MARK: Selection

    private func deselect() { selected = nil; needsDisplay = true }

    func deleteSelected() {
        guard let sel = selected else { return }
        pushUndo()
        annotations.removeAll { $0 === sel }
        selected = nil
        needsDisplay = true
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        endTextEditing(commit: true)
        let ip = imagePoint(e)
        dragOrigin = ip

        if tool == .select {
            // resize handle? (undo is deferred until the first real drag)
            if let sel = selected {
                let handles = sel.handlePositions()
                for (i, h) in handles.enumerated() {
                    if hypot(vp(h).x - vp(ip).x, vp(h).y - vp(ip).y) <= 8 {
                        dragMode = .resizing; activeHandle = i
                        resizingRect = handles.count == 4
                        if resizingRect { resizeAnchor = handles[(i + 2) % 4] }
                        pendingUndo = true
                        return
                    }
                }
            }
            // body hit?
            if let hit = annotations.reversed().first(where: { $0.hitTest(ip, tolerance: 6 / zoom) }) {
                selected = hit; dragMode = .moving; pendingUndo = true; needsDisplay = true
            } else {
                deselect(); dragMode = .none
            }
            return
        }

        switch tool {
        case .counter:
            pushUndo()
            let a = Annotation(kind: .counter, color: strokeColor, lineWidth: lineWidth, start: ip, end: ip)
            a.number = counterValue; a.fontSize = 16 + lineWidth * 2
            counterValue += 1
            annotations.append(a); selected = a; dragMode = .none; needsDisplay = true
            onStateChange?()
        case .text:
            pushUndo()
            textSnapshotPending = true
            let a = Annotation(kind: .text, color: strokeColor, lineWidth: lineWidth, start: ip, end: ip)
            a.fontSize = 16 + lineWidth * 3
            annotations.append(a); selected = a
            beginTextEditing(a)
        case .pen:
            pushUndo()
            let a = Annotation(kind: .pen, color: strokeColor, lineWidth: lineWidth, start: ip, end: ip)
            a.points = [ip]
            draft = a; dragMode = .creating
        default:
            // drag shapes
            pushUndo()
            let kind = kindFor(tool)
            let a = Annotation(kind: kind, color: strokeColor, lineWidth: lineWidth, start: ip, end: ip)
            draft = a; dragMode = .creating
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let ip = imagePoint(e)
        switch dragMode {
        case .creating:
            if let d = draft {
                if d.kind == .pen { d.points.append(ip) } else { d.end = ip }
                needsDisplay = true
            }
        case .moving:
            if let sel = selected {
                if pendingUndo { pushUndo(); pendingUndo = false }
                sel.translate(by: CGVector(dx: ip.x - dragOrigin.x, dy: ip.y - dragOrigin.y))
                dragOrigin = ip; needsDisplay = true
            }
        case .resizing:
            if let sel = selected {
                if pendingUndo { pushUndo(); pendingUndo = false }
                if resizingRect { sel.resizeRect(anchor: resizeAnchor, corner: ip) }
                else { sel.resize(handleIndex: activeHandle, to: ip) }
                needsDisplay = true
            }
        case .none:
            break
        }
    }

    override func mouseUp(with e: NSEvent) {
        if dragMode == .creating, let d = draft {
            let ok = d.kind == .pen ? d.points.count > 1 : (abs(d.end.x - d.start.x) > 3 || abs(d.end.y - d.start.y) > 3)
            if tool == .crop {
                if ok { commitCrop(rect: d.rect) } else { undoStack.removeLast() }
            } else if ok {
                annotations.append(d)
                selected = d
                if tool != .select { /* keep tool */ }
            } else {
                undoStack.removeLast() // nothing created; drop the undo snapshot
            }
        }
        draft = nil
        dragMode = .none
        activeHandle = -1
        pendingUndo = false
        resizingRect = false
        needsDisplay = true
        onStateChange?()
    }

    override func mouseMoved(with e: NSEvent) {
        let ip = imagePoint(e)
        let color = colorAt(imagePoint: ip)
        onHover?(color, ip)
    }

    private func kindFor(_ tool: Tool) -> Annotation.Kind {
        switch tool {
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .roundedRect: return .roundedRect
        case .ellipse: return .ellipse
        case .highlight: return .highlight
        case .blur: return .blur
        case .pixelate: return .pixelate
        case .crop: return .rectangle // crop uses rect geometry; handled specially
        default: return .rectangle
        }
    }

    // MARK: Keyboard

    override func keyDown(with e: NSEvent) {
        let code = Int(e.keyCode)
        if code == kVK_Escape { endTextEditing(commit: true); deselect(); return }
        if code == kVK_Delete || code == kVK_ForwardDelete { deleteSelected(); return }
        if code == kVK_Tab { // "Tab to copy" hovered colour
            let pb = NSPasteboard.general; pb.clearContents(); pb.setString(lastHoverColor.hexString, forType: .string)
            HUD.show("Copied \(lastHoverColor.hexString)")
            return
        }
        // ⌘Z / ⇧⌘Z undo-redo
        if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers?.lowercased() == "z" {
            if e.modifierFlags.contains(.shift) { redo() } else { undo() }
            return
        }
        // Plain-letter tool switch (ignored while a modifier is held or text is being edited).
        if e.modifierFlags.intersection([.command, .control, .option]).isEmpty, textEditor == nil,
           let ch = e.charactersIgnoringModifiers?.lowercased(),
           let t = Tool.allCases.first(where: { $0.shortcut == ch }) {
            tool = t; onToolChange?(t); return
        }
        // arrow nudges for the selection
        if let sel = selected, [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(code) {
            let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
            var d = CGVector.zero
            if code == kVK_LeftArrow { d.dx = -step }; if code == kVK_RightArrow { d.dx = step }
            if code == kVK_UpArrow { d.dy = -step }; if code == kVK_DownArrow { d.dy = step }
            pushUndo(); sel.translate(by: d); needsDisplay = true
            return
        }
        super.keyDown(with: e)
    }

    private var lastHoverColor: NSColor = .black

    private func colorAt(imagePoint ip: CGPoint) -> NSColor {
        let x = Int((ip.x * captureScale).rounded()), y = Int((ip.y * captureScale).rounded())
        guard x >= 0, y >= 0, x < source.width, y < source.height,
              let rep = cachedRep ?? NSBitmapImageRep(cgImage: source) as NSBitmapImageRep? else { return .black }
        cachedRep = rep
        let c = rep.colorAt(x: x, y: y) ?? .black
        lastHoverColor = c
        return c
    }
    private var cachedRep: NSBitmapImageRep?

    // MARK: Crop

    private func commitCrop(rect: CGRect) {
        let pxRect = CGRect(x: rect.minX * captureScale, y: rect.minY * captureScale,
                            width: rect.width * captureScale, height: rect.height * captureScale).integral
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let clamped = pxRect.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1, let cropped = source.cropping(to: clamped) else { return }
        // pushUndo already done at mouseDown for the draft
        source = cropped
        cachedRep = nil
        let d = CGVector(dx: -clamped.minX / captureScale, dy: -clamped.minY / captureScale)
        for a in annotations { a.translate(by: d) }
        tool = .select
        setZoom(zoom)
        needsDisplay = true
        onStateChange?()
    }

    // MARK: Text editing

    private func beginTextEditing(_ a: Annotation) {
        endTextEditing(commit: true)
        editingAnnotation = a
        let origin = vp(a.start)
        let tv = NSTextView(frame: NSRect(x: origin.x, y: origin.y, width: 240, height: a.fontSize * zoom + 12))
        tv.isFieldEditor = false
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        tv.textColor = a.color
        tv.font = NSFont.systemFont(ofSize: a.fontSize * zoom, weight: .semibold)
        tv.string = a.text
        tv.delegate = self
        tv.isRichText = false
        addSubview(tv)
        window?.makeFirstResponder(tv)
        textEditor = tv
    }

    private func endTextEditing(commit: Bool) {
        guard let tv = textEditor, let a = editingAnnotation else { return }
        if commit { a.text = tv.string }
        if a.text.isEmpty {
            annotations.removeAll { $0 === a }
            // The text was created but never given content — drop its orphaned undo snapshot.
            if textSnapshotPending, !undoStack.isEmpty { undoStack.removeLast() }
        }
        textSnapshotPending = false
        tv.removeFromSuperview()
        textEditor = nil
        editingAnnotation = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
        onStateChange?()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: bounds)
        NSImage(cgImage: source, size: imagePointSize).draw(in: bounds)
        for a in annotations where a !== editingAnnotation {
            a.draw(v: vp, zoom: zoom, source: source, captureScale: captureScale)
        }
        if let d = draft {
            if d.kind == .rectangle && tool == .crop { drawCropDraft(d.rect) }
            else { d.draw(v: vp, zoom: zoom, source: source, captureScale: captureScale) }
        }
        if let sel = selected { drawSelection(sel) }
    }

    private func drawCheckerboard(in rect: NSRect) {
        NSColor(calibratedWhite: 0.17, alpha: 1).setFill(); rect.fill()
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        let s: CGFloat = 10
        var y: CGFloat = 0, row = 0
        while y < rect.height {
            var x: CGFloat = (row % 2 == 0) ? 0 : s
            while x < rect.width {
                NSBezierPath(rect: NSRect(x: x, y: y, width: s, height: s)).fill()
                x += 2 * s
            }
            y += s; row += 1
        }
    }

    private func drawSelection(_ a: Annotation) {
        let box = a.boundingBox
        let vr = CGRect(x: box.minX * zoom, y: box.minY * zoom, width: box.width * zoom, height: box.height * zoom)
        NSColor.systemBlue.setStroke()
        let p = NSBezierPath(rect: vr); p.lineWidth = 1
        p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        for h in a.handlePositions() {
            let c = vp(h)
            let hr = NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
            NSColor.white.setFill(); NSBezierPath(ovalIn: hr).fill()
            NSColor.systemBlue.setStroke(); NSBezierPath(ovalIn: hr).stroke()
        }
    }

    private func drawCropDraft(_ rect: CGRect) {
        NSColor.black.withAlphaComponent(0.45).setFill(); bounds.fill()
        let vr = CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState(); NSBezierPath(rect: vr).setClip()
            NSImage(cgImage: source, size: imagePointSize).draw(in: bounds)
            ctx.restoreGraphicsState()
        }
        NSColor.white.setStroke(); let b = NSBezierPath(rect: vr); b.lineWidth = 1; b.stroke()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = tool == .select ? .arrow : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Export

    /// Composited image (image + annotations, no selection chrome) at native resolution.
    func compositedImage() -> NSImage {
        let img = NSImage(size: imagePointSize)
        img.lockFocusFlipped(true)
        NSImage(cgImage: source, size: imagePointSize).draw(in: NSRect(origin: .zero, size: imagePointSize))
        for a in annotations { a.draw(v: { $0 }, zoom: 1, source: source, captureScale: captureScale) }
        img.unlockFocus()
        return img
    }

    func compositedPNG() -> Data? {
        let img = compositedImage()
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        rep.size = imagePointSize
        return rep.representation(using: .png, properties: [:])
    }
}

extension EditorCanvasView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if let tv = textEditor, let a = editingAnnotation {
            a.text = tv.string
            let size = (tv.string as NSString).size(withAttributes: [.font: tv.font as Any])
            tv.frame.size.width = max(60, size.width + 20)
        }
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            endTextEditing(commit: true); return true
        }
        return false
    }
}
