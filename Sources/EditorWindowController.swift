import AppKit

/// The editor window: dark chrome, a Shottr-style toolbar (output actions + tools + colour/width),
/// a top-right HUD (image size · zoom · hovered colour), and the scrollable canvas.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let canvas: EditorCanvasView
    private let scrollView = NSScrollView()
    var onClose: (() -> Void)?

    private var toolButtons: [Tool: NSButton] = [:]
    private let sizeLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let hexLabel = NSTextField(labelWithString: "#000000")
    private let colorSwatch = NSView()
    private let colorWell = NSColorWell()

    private let barHeight: CGFloat = 46

    init(captured: CapturedImage) {
        canvas = EditorCanvasView(captured: captured)

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let imgSize = canvas.imagePointSize
        let maxW = min(imgSize.width, visible.width * 0.9)
        let maxH = min(imgSize.height, visible.height * 0.9 - barHeight)
        let contentW = max(760, maxW)
        let contentH = maxH + barHeight

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = "Screenshots — \(Int(imgSize.width)) × \(Int(imgSize.height))"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 320)
        window.center()

        buildUI(contentSize: NSSize(width: contentW, height: contentH))

        canvas.onStateChange = { [weak self] in self?.refreshHUD() }
        canvas.onHover = { [weak self] color, _ in self?.updateHoverColor(color) }
        canvas.onToolChange = { [weak self] t in self?.highlightTool(t) }
        highlightTool(canvas.tool)
        refreshHUD()
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        DispatchQueue.main.async { [weak self] in self?.canvas.zoomToFit() }
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: UI construction

    private func buildUI(contentSize: NSSize) {
        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        content.wantsLayer = true
        window.contentView = content

        // Bar
        let bar = NSView(frame: NSRect(x: 0, y: contentSize.height - barHeight, width: contentSize.width, height: barHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        content.addSubview(bar)

        // Scroll view + canvas
        scrollView.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height - barHeight)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        scrollView.drawsBackground = true
        scrollView.documentView = canvas
        content.addSubview(scrollView)

        // Left group: output actions
        let copyBtn = makeActionButton("doc.on.doc", "Copy", "c", #selector(copyImage))
        let saveBtn = makeActionButton("square.and.arrow.down", "Save", "s", #selector(saveImage))
        let pinBtn = makeActionButton("pin", "Pin", "p", #selector(pinImage))
        let leftGroup = NSStackView(views: [copyBtn, saveBtn, pinBtn, makeDivider()])
        leftGroup.orientation = .horizontal
        leftGroup.spacing = 4
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

        // Tools
        let toolViews: [NSView] = Tool.allCases.map { makeToolButton($0) }
        let toolGroup = NSStackView(views: toolViews)
        toolGroup.orientation = .horizontal
        toolGroup.spacing = 2
        toolGroup.translatesAutoresizingMaskIntoConstraints = false

        // Color + width
        colorWell.color = canvas.strokeColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 34).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let widthControl = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne, target: self, action: #selector(widthChanged))
        widthControl.selectedSegment = 1
        widthControl.translatesAutoresizingMaskIntoConstraints = false

        let midGroup = NSStackView(views: [makeDivider(), colorWell, widthControl])
        midGroup.orientation = .horizontal
        midGroup.spacing = 6
        midGroup.translatesAutoresizingMaskIntoConstraints = false

        // Right HUD
        colorSwatch.wantsLayer = true
        colorSwatch.layer?.borderColor = NSColor(white: 1, alpha: 0.4).cgColor
        colorSwatch.layer?.borderWidth = 1
        colorSwatch.layer?.cornerRadius = 2
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false
        colorSwatch.widthAnchor.constraint(equalToConstant: 14).isActive = true
        colorSwatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
        for l in [sizeLabel, zoomLabel, hexLabel] {
            l.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            l.textColor = NSColor(white: 0.75, alpha: 1)
        }
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let hudGroup = NSStackView(views: [colorSwatch, hexLabel, makeDivider(), sizeLabel, zoomLabel])
        hudGroup.orientation = .horizontal
        hudGroup.spacing = 8
        hudGroup.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(leftGroup)
        bar.addSubview(toolGroup)
        bar.addSubview(midGroup)
        bar.addSubview(hudGroup)

        NSLayoutConstraint.activate([
            leftGroup.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            leftGroup.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            toolGroup.leadingAnchor.constraint(equalTo: leftGroup.trailingAnchor, constant: 8),
            toolGroup.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            midGroup.leadingAnchor.constraint(equalTo: toolGroup.trailingAnchor, constant: 10),
            midGroup.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            hudGroup.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            hudGroup.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    private func makeDivider() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    private func styleGlyph(_ button: NSButton, symbol: String, fallback: String) {
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.contentTintColor = NSColor(white: 0.85, alpha: 1)
        } else {
            button.title = fallback
            button.font = NSFont.systemFont(ofSize: 14)
        }
    }

    private func makeActionButton(_ symbol: String, _ title: String, _ key: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.setButtonType(.momentaryPushIn)
        styleGlyph(b, symbol: symbol, fallback: title)
        b.toolTip = "\(title) (⌘\(key.uppercased()))"
        b.keyEquivalent = key
        b.keyEquivalentModifierMask = .command
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func makeToolButton(_ tool: Tool) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(toolButtonClicked(_:)))
        b.bezelStyle = .texturedRounded
        b.setButtonType(.pushOnPushOff)
        styleGlyph(b, symbol: tool.symbolName, fallback: tool.fallbackGlyph)
        b.toolTip = "\(tool.title) (\(tool.shortcut.uppercased()))"
        b.tag = Tool.allCases.firstIndex(of: tool) ?? 0
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        toolButtons[tool] = b
        return b
    }

    // MARK: Actions

    @objc private func toolButtonClicked(_ sender: NSButton) {
        let tool = Tool.allCases[sender.tag]
        canvas.tool = tool
        highlightTool(tool)
    }

    private func highlightTool(_ tool: Tool) {
        for (t, b) in toolButtons {
            let on = t == tool
            b.state = on ? .on : .off
            b.contentTintColor = on ? .systemBlue : NSColor(white: 0.85, alpha: 1)
        }
    }

    @objc private func colorChanged() {
        canvas.strokeColor = colorWell.color
    }

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        canvas.lineWidth = [2.5, 4.0, 7.0][max(0, min(2, sender.selectedSegment))]
    }

    @objc private func copyImage() {
        let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([canvas.compositedImage()])
        HUD.show("Copied to clipboard")
    }

    @objc private func saveImage() {
        guard let data = canvas.compositedPNG() else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dir = Config.shared.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Screenshot \(df.string(from: Date())).png")
        do { try data.write(to: url); HUD.show("Saved \(url.lastPathComponent)") }
        catch { HUD.show("Save failed") }
    }

    @objc private func pinImage() {
        PinController.shared.pin(canvas.compositedImage(), at: nil)
        HUD.show("Pinned")
    }

    // MARK: HUD

    private func refreshHUD() {
        let s = canvas.imagePointSize
        sizeLabel.stringValue = "\(Int(s.width)) × \(Int(s.height))"
        zoomLabel.stringValue = "\(Int((canvas.zoom * 100).rounded()))%"
        window.title = "Screenshots — \(Int(s.width)) × \(Int(s.height))"
    }

    private func updateHoverColor(_ color: NSColor) {
        colorSwatch.layer?.backgroundColor = color.cgColor
        hexLabel.stringValue = color.hexString
    }
}
