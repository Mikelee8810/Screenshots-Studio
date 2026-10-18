import SwiftUI
import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var editorWindow: NSWindow?
    var libraryWindow: NSWindow?
    var preferencesWindow: NSWindow?
    var capturedImage: NSImage?
    var recordMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = AppIconGenerator.makeAppIcon(size: 512)
        ThemeManager.shared.applyWindowAppearance()
        setupMainMenu()
        setupMenuBar()
        setupNotificationObservers()
        setupGlobalHotkeys()
        setupGlobalURLHandler()
        openEditor(with: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { PermissionManager.promptIfNeeded() }
    }

    func setupNotificationObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(showLibraryAction), name: Notification.Name("ScreenshotsOpenLibrary"), object: nil)
        nc.addObserver(self, selector: #selector(showPreferencesAction), name: Notification.Name("ScreenshotsOpenPreferences"), object: nil)
        nc.addObserver(self, selector: #selector(captureAreaAction), name: Notification.Name("ScreenshotsTriggerArea"), object: nil)
        nc.addObserver(self, selector: #selector(captureAnyWindowAction), name: Notification.Name("ScreenshotsTriggerWindow"), object: nil)
        nc.addObserver(self, selector: #selector(captureFullscreenAction), name: Notification.Name("ScreenshotsTriggerFullscreen"), object: nil)
        nc.addObserver(self, selector: #selector(captureScrollingDownAction), name: Notification.Name("ScreenshotsTriggerScrolling"), object: nil)
        nc.addObserver(self, selector: #selector(setupGlobalHotkeys), name: ShortcutStore.changedNotification, object: nil)
        nc.addObserver(self, selector: #selector(updateEditorWindowLevel), name: Notification.Name("ScreenshotsUpdateWindowLevel"), object: nil)
    }

    func hotkeyHandler(for action: HotkeyAction) -> () -> Void {
        switch action {
        case .fullscreen: return { [weak self] in self?.captureFullscreenAction() }
        case .area: return { [weak self] in self?.captureAreaAction() }
        case .scrollDown: return { [weak self] in self?.captureScrollingDownAction() }
        case .scrollUp: return { [weak self] in self?.captureScrollingUpAction() }
        case .anyWindow: return { [weak self] in self?.captureAnyWindowAction() }
        case .activeWindow: return { [weak self] in self?.captureActiveWindowAction() }
        case .repeatArea: return { [weak self] in self?.captureRepeatAreaAction() }
        case .ocr: return { [weak self] in self?.captureOCRAction() }
        case .delayed: return { [weak self] in self?.captureDelayedAction() }
        case .record: return { [weak self] in self?.toggleRecordingAction() }
        }
    }

    @objc func setupGlobalHotkeys() {
        let hk = GlobalHotkeys.shared
        hk.unregisterAll()
        for action in HotkeyAction.allCases {
            guard let b = ShortcutStore.shared.bindings[action] else { continue }
            hk.register(keyCode: b.keyCode, modifiers: b.mods, handler: hotkeyHandler(for: action))
        }
        if statusItem?.menu != nil { setupMenuBar() }
    }

    @objc func toggleRecordingAction() {
        let rec = ScreenRecorder.shared
        if rec.isRecording {
            rec.stop { [weak self] url in
                DispatchQueue.main.async {
                    self?.statusItem?.button?.title = ""
                    self?.recordMenuItem?.title = "Start Screen Recording"
                    if let url = url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        } else {
            editorWindow?.orderOut(nil)
            rec.start { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        let alert = NSAlert()
                        alert.messageText = "Couldn't start recording"
                        alert.informativeText = error.localizedDescription + "\n\nCheck System Settings > Privacy & Security > Screen Recording."
                        alert.runModal()
                    } else {
                        self?.statusItem?.button?.title = " ● REC"
                        self?.recordMenuItem?.title = "Stop Screen Recording"
                    }
                }
            }
        }
    }

    @objc func gifFromLastRecordingAction() {
        guard let url = ScreenRecorder.shared.lastRecordingURL, FileManager.default.fileExists(atPath: url.path) else {
            let alert = NSAlert()
            alert.messageText = "No recording yet"
            alert.informativeText = "Record your screen first, then convert it to a GIF."
            alert.runModal()
            return
        }
        ScreenRecorder.shared.exportGIF(from: url) { gif in
            DispatchQueue.main.async {
                if let gif = gif { NSWorkspace.shared.activateFileViewerSelecting([gif]) }
            }
        }
    }

    func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Screenshots", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showPreferencesAction), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Screenshots", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Screenshots", action: #selector(quitAction), keyEquivalent: "q")

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open Image…", action: #selector(openFileAction), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Screenshot Library", action: #selector(showLibraryAction), keyEquivalent: "l")

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    func applyShortcutsToMenu(_ menu: NSMenu) {
        let map: [Selector: HotkeyAction] = [
            #selector(captureFullscreenAction): .fullscreen,
            #selector(captureAreaAction): .area,
            #selector(captureScrollingDownAction): .scrollDown,
            #selector(captureScrollingUpAction): .scrollUp,
            #selector(captureAnyWindowAction): .anyWindow,
            #selector(captureActiveWindowAction): .activeWindow,
            #selector(captureRepeatAreaAction): .repeatArea,
            #selector(captureOCRAction): .ocr,
            #selector(captureDelayedAction): .delayed,
            #selector(toggleRecordingAction): .record
        ]
        for item in menu.items {
            guard let sel = item.action, let action = map[sel], let b = ShortcutStore.shared.bindings[action] else { continue }
            item.keyEquivalent = b.label.lowercased()
            item.keyEquivalentModifierMask = b.menuMask
        }
    }

    @objc func updateEditorWindowLevel() {
        let floatOnTop = UserDefaults.standard.bool(forKey: "editorAlwaysOnTop")
        editorWindow?.level = floatOnTop ? .floating : .normal
    }

    func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.image = AppIconGenerator.makeMenuBarIcon()
            }
        }

        let menu = NSMenu()

        let showEditorItem = NSMenuItem(title: "Open Screenshots Studio", action: #selector(showEditorAction), keyEquivalent: "s")
        showEditorItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(showEditorItem)

        let libItem = NSMenuItem(title: "Screenshot Library & OCR Search...", action: #selector(showLibraryAction), keyEquivalent: "l")
        libItem.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)
        menu.addItem(libItem)

        menu.addItem(NSMenuItem.separator())

        let fullItem = NSMenuItem(title: "Fullscreen Screenshot", action: #selector(captureFullscreenAction), keyEquivalent: "1")
        fullItem.keyEquivalentModifierMask = [.command, .shift]
        fullItem.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        menu.addItem(fullItem)

        let areaItem = NSMenuItem(title: "Area Screenshot", action: #selector(captureAreaAction), keyEquivalent: "4")
        areaItem.keyEquivalentModifierMask = [.command, .shift]
        areaItem.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        menu.addItem(areaItem)

        let repeatAreaItem = NSMenuItem(title: "Repeat Area Capture", action: #selector(captureRepeatAreaAction), keyEquivalent: "r")
        repeatAreaItem.keyEquivalentModifierMask = [.command, .shift]
        repeatAreaItem.image = NSImage(systemSymbolName: "arrow.clockwise.square", accessibilityDescription: nil)
        menu.addItem(repeatAreaItem)

        let anyWinItem = NSMenuItem(title: "Capture Any Window", action: #selector(captureAnyWindowAction), keyEquivalent: "w")
        anyWinItem.keyEquivalentModifierMask = [.command, .shift]
        anyWinItem.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        menu.addItem(anyWinItem)

        let activeWinItem = NSMenuItem(title: "Capture Active Window", action: #selector(captureActiveWindowAction), keyEquivalent: "a")
        activeWinItem.keyEquivalentModifierMask = [.command, .shift]
        activeWinItem.image = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: nil)
        menu.addItem(activeWinItem)

        menu.addItem(NSMenuItem.separator())

        let scrollDownItem = NSMenuItem(title: "Scrolling Capture (Down)", action: #selector(captureScrollingDownAction), keyEquivalent: "5")
        scrollDownItem.keyEquivalentModifierMask = [.option, .shift]
        scrollDownItem.image = NSImage(systemSymbolName: "arrow.up.and.down.text.horizontal", accessibilityDescription: nil)
        menu.addItem(scrollDownItem)

        let scrollUpItem = NSMenuItem(title: "Reverse Scrolling Capture (Up)", action: #selector(captureScrollingUpAction), keyEquivalent: "4")
        scrollUpItem.keyEquivalentModifierMask = [.option, .shift]
        scrollUpItem.image = NSImage(systemSymbolName: "arrow.up.doc", accessibilityDescription: nil)
        menu.addItem(scrollUpItem)

        let delayedItem = NSMenuItem(title: "Delayed Screenshot (3s)", action: #selector(captureDelayedAction), keyEquivalent: "d")
        delayedItem.keyEquivalentModifierMask = [.command, .shift]
        delayedItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        menu.addItem(delayedItem)

        let recordItem = NSMenuItem(title: ScreenRecorder.shared.isRecording ? "Stop Screen Recording" : "Start Screen Recording", action: #selector(toggleRecordingAction), keyEquivalent: "5")
        recordItem.keyEquivalentModifierMask = [.control, .shift]
        recordItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        menu.addItem(recordItem)
        recordMenuItem = recordItem

        let gifItem = NSMenuItem(title: "Convert Last Recording to GIF", action: #selector(gifFromLastRecordingAction), keyEquivalent: "")
        gifItem.image = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: nil)
        menu.addItem(gifItem)

        menu.addItem(NSMenuItem.separator())

        let ocrItem = NSMenuItem(title: "Recognize Text / QR Code", action: #selector(captureOCRAction), keyEquivalent: "o")
        ocrItem.keyEquivalentModifierMask = [.control, .option, .command]
        ocrItem.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: nil)
        menu.addItem(ocrItem)

        let clipboardItem = NSMenuItem(title: "Load From Clipboard", action: #selector(loadClipboardAction), keyEquivalent: "v")
        clipboardItem.keyEquivalentModifierMask = [.command]
        clipboardItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(clipboardItem)

        let openFileItem = NSMenuItem(title: "Open Image File...", action: #selector(openFileAction), keyEquivalent: "o")
        openFileItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(openFileItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesAction), keyEquivalent: ",")
        prefsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem(title: "Quit Screenshots", action: #selector(quitAction), keyEquivalent: "q"))

        applyShortcutsToMenu(menu)
        statusItem?.menu = menu
    }

    private func handlePostCapture(_ image: NSImage?) {
        guard let image = image else {
            if self.capturedImage != nil {
                DispatchQueue.main.async {
                    self.editorWindow?.makeKeyAndOrderFront(nil)
                }
            }
            return
        }

        if UserDefaults.standard.object(forKey: "afterGrabCopy") == nil || UserDefaults.standard.bool(forKey: "afterGrabCopy") {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }

        if UserDefaults.standard.bool(forKey: "afterGrabSave"),
           let tiff = image.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            let url = ScreenCaptureManager.shared.defaultSaveFolder
                .appendingPathComponent("SCR-\(Int(Date().timeIntervalSince1970)).png")
            try? png.write(to: url)
        }

        ThumbnailPreviewManager.shared.showThumbnail(
            for: image,
            onEdit: { [weak self] img in
                self?.openEditor(with: img)
            },
            onPin: { [weak self] img in
                PinWindowManager.shared.pinImage(img) { edited in
                    self?.openEditor(with: edited)
                }
            },
            onOCR: { img in
                ScreenCaptureManager.shared.recognizeTextAndQR(in: img) { text in
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
            },
            onSave: { img in
                guard let tiff = img.tiffRepresentation,
                      let bmp = NSBitmapImageRep(data: tiff),
                      let png = bmp.representation(using: .png, properties: [:]) else { return }
                let folder = ScreenCaptureManager.shared.defaultSaveFolder
                let url = folder.appendingPathComponent("SCR-\(Int(Date().timeIntervalSince1970)).png")
                try? png.write(to: url)
            }
        )

        if UserDefaults.standard.object(forKey: "afterGrabShow") == nil || UserDefaults.standard.bool(forKey: "afterGrabShow") {
            openEditor(with: image)
        }
    }

    @objc func showEditorAction() {
        openEditor(with: capturedImage)
    }

    @objc func captureAreaAction() {
        editorWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            ScreenCaptureManager.shared.captureInteractiveArea { img in
                self?.handlePostCapture(img)
            }
        }
    }

    @objc func captureRepeatAreaAction() {
        ScreenCaptureManager.shared.captureRepeatArea { [weak self] img in
            self?.handlePostCapture(img)
        }
    }

    @objc func captureFullscreenAction() {
        editorWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            ScreenCaptureManager.shared.captureFullScreen { img in
                self?.handlePostCapture(img)
            }
        }
    }

    @objc func captureAnyWindowAction() {
        editorWindow?.orderOut(nil)
        let shadow = UserDefaults.standard.bool(forKey: "windowShadow")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            ScreenCaptureManager.shared.captureAnyWindow(includeShadow: shadow) { img in
                self?.handlePostCapture(img)
            }
        }
    }

    @objc func captureActiveWindowAction() {
        editorWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            ScreenCaptureManager.shared.captureActiveWindow { img in
                self?.handlePostCapture(img)
            }
        }
    }

    @objc func captureScrollingDownAction() {
        editorWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            ScreenCaptureManager.shared.captureScrollingArea(reverseDirection: false) { img in
                self?.handlePostCapture(img)
            }
        }
    }

    @objc func captureScrollingUpAction() {
        editorWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            ScreenCaptureManager.shared.captureScrollingArea(reverseDirection: true) { img in
                self?.handlePostCapture(img)
            }
        }
    }

    @objc func captureDelayedAction() {
        editorWindow?.orderOut(nil)
        ScreenCaptureManager.shared.captureDelayed(seconds: 3) { [weak self] img in
            self?.handlePostCapture(img)
        }
    }

    @objc func captureOCRAction() {
        editorWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ScreenCaptureManager.shared.captureInteractiveArea { img in
                guard let img = img else { return }
                let removeBreaks = UserDefaults.standard.bool(forKey: "ocrRemoveBreaks")
                ScreenCaptureManager.shared.recognizeTextAndQR(in: img, removeLineBreaks: removeBreaks) { text in
                    guard !text.isEmpty else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)

                    let alert = NSAlert()
                    alert.messageText = "Text & QR Copied to Clipboard"
                    alert.informativeText = text
                    alert.runModal()
                }
            }
        }
    }

    @objc func loadClipboardAction() {
        let pb = NSPasteboard.general
        if let img = NSImage(pasteboard: pb) {
            openEditor(with: img)
        }
    }

    @objc func openFileAction() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            openEditor(with: img)
        }
    }

    // MARK: - Studio Window Controllers (Defaults to Standard .normal Window Level)
    func openEditor(with image: NSImage?) {
        if let image = image {
            self.capturedImage = image
        }

        if editorWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Screenshots Studio"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            self.editorWindow = window
        }

        // Default to FALSE (.normal) so user can place window behind any other app!
        let floatOnTop = UserDefaults.standard.bool(forKey: "editorAlwaysOnTop")
        editorWindow?.level = floatOnTop ? .floating : .normal

        let contentView = EditorView(image: Binding(
            get: { self.capturedImage },
            set: { self.capturedImage = $0 }
        ))

        editorWindow?.contentView = NSHostingView(rootView: contentView)
        editorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showLibraryAction() {
        if libraryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Screenshots Library"
            window.titlebarAppearsTransparent = true
            window.level = .normal
            window.isReleasedWhenClosed = false
            self.libraryWindow = window
        }

        let libView = LibraryBrowserView { [weak self] selectedImg in
            self?.libraryWindow?.close()
            self?.openEditor(with: selectedImg)
        }
        libraryWindow?.contentView = NSHostingView(rootView: libView)
        libraryWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showPreferencesAction() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 470),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Screenshots Settings"
            window.titlebarAppearsTransparent = true
            window.level = .normal
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView())
            self.preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupGlobalURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        let path = url.host ?? ""
        switch path {
        case "grab":
            if url.path.contains("area") { captureAreaAction() }
            else if url.path.contains("fullscreen") { captureFullscreenAction() }
            else if url.path.contains("window") { captureActiveWindowAction() }
            else if url.path.contains("scrolling") { captureScrollingDownAction() }
        case "ocr":
            captureOCRAction()
        case "load":
            if url.path.contains("clipboard") { loadClipboardAction() }
        default:
            showEditorAction()
        }
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

if let idx = CommandLine.arguments.firstIndex(of: "--export-iconset"), idx + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let dir = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024)
    ]
    let source = AppIconGenerator.makeAppIcon(size: 1024)
    for (name, px) in sizes {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
