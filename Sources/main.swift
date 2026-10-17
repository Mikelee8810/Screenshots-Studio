import SwiftUI
import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var editorWindow: NSWindow?
    var libraryWindow: NSWindow?
    var preferencesWindow: NSWindow?
    var capturedImage: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = AppIconGenerator.makeAppIcon(size: 512)
        ThemeManager.shared.applyWindowAppearance()
        setupMenuBar()
        setupNotificationObservers()
        setupGlobalHotkeys()
        setupGlobalURLHandler()
        openEditor(with: nil)
    }

    func setupNotificationObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(showLibraryAction), name: Notification.Name("ScreenshotsOpenLibrary"), object: nil)
        nc.addObserver(self, selector: #selector(showPreferencesAction), name: Notification.Name("ScreenshotsOpenPreferences"), object: nil)
        nc.addObserver(self, selector: #selector(captureAreaAction), name: Notification.Name("ScreenshotsTriggerArea"), object: nil)
        nc.addObserver(self, selector: #selector(captureAnyWindowAction), name: Notification.Name("ScreenshotsTriggerWindow"), object: nil)
        nc.addObserver(self, selector: #selector(captureFullscreenAction), name: Notification.Name("ScreenshotsTriggerFullscreen"), object: nil)
        nc.addObserver(self, selector: #selector(captureScrollingDownAction), name: Notification.Name("ScreenshotsTriggerScrolling"), object: nil)
        nc.addObserver(self, selector: #selector(updateEditorWindowLevel), name: Notification.Name("ScreenshotsUpdateWindowLevel"), object: nil)
    }

    func setupGlobalHotkeys() {
        let mods = controlKey | shiftKey
        let hk = GlobalHotkeys.shared
        hk.register(keyCode: kVK_ANSI_1, modifiers: mods) { [weak self] in self?.captureFullscreenAction() }
        hk.register(keyCode: kVK_ANSI_2, modifiers: mods) { [weak self] in self?.captureAreaAction() }
        hk.register(keyCode: kVK_ANSI_3, modifiers: mods) { [weak self] in self?.captureScrollingDownAction() }
        hk.register(keyCode: kVK_ANSI_4, modifiers: mods) { [weak self] in self?.captureScrollingUpAction() }
        hk.register(keyCode: kVK_ANSI_W, modifiers: mods) { [weak self] in self?.captureAnyWindowAction() }
        hk.register(keyCode: kVK_ANSI_A, modifiers: mods) { [weak self] in self?.captureActiveWindowAction() }
        hk.register(keyCode: kVK_ANSI_R, modifiers: mods) { [weak self] in self?.captureRepeatAreaAction() }
        hk.register(keyCode: kVK_ANSI_O, modifiers: mods) { [weak self] in self?.captureOCRAction() }
        hk.register(keyCode: kVK_ANSI_D, modifiers: mods) { [weak self] in self?.captureDelayedAction() }
    }

    @objc func updateEditorWindowLevel() {
        let floatOnTop = UserDefaults.standard.bool(forKey: "editorAlwaysOnTop")
        editorWindow?.level = floatOnTop ? .floating : .normal
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = AppIconGenerator.makeMenuBarIcon()
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
        fullItem.keyEquivalentModifierMask = [.control, .shift]
        fullItem.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        menu.addItem(fullItem)

        let areaItem = NSMenuItem(title: "Area Screenshot", action: #selector(captureAreaAction), keyEquivalent: "2")
        areaItem.keyEquivalentModifierMask = [.control, .shift]
        areaItem.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        menu.addItem(areaItem)

        let repeatAreaItem = NSMenuItem(title: "Repeat Area Capture", action: #selector(captureRepeatAreaAction), keyEquivalent: "r")
        repeatAreaItem.keyEquivalentModifierMask = [.control, .shift]
        repeatAreaItem.image = NSImage(systemSymbolName: "arrow.clockwise.square", accessibilityDescription: nil)
        menu.addItem(repeatAreaItem)

        let anyWinItem = NSMenuItem(title: "Capture Any Window", action: #selector(captureAnyWindowAction), keyEquivalent: "w")
        anyWinItem.keyEquivalentModifierMask = [.control, .shift]
        anyWinItem.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        menu.addItem(anyWinItem)

        let activeWinItem = NSMenuItem(title: "Capture Active Window", action: #selector(captureActiveWindowAction), keyEquivalent: "a")
        activeWinItem.keyEquivalentModifierMask = [.control, .shift]
        activeWinItem.image = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: nil)
        menu.addItem(activeWinItem)

        menu.addItem(NSMenuItem.separator())

        let scrollDownItem = NSMenuItem(title: "Scrolling Capture (Down)", action: #selector(captureScrollingDownAction), keyEquivalent: "3")
        scrollDownItem.keyEquivalentModifierMask = [.control, .shift]
        scrollDownItem.image = NSImage(systemSymbolName: "arrow.up.and.down.text.horizontal", accessibilityDescription: nil)
        menu.addItem(scrollDownItem)

        let scrollUpItem = NSMenuItem(title: "Reverse Scrolling Capture (Up)", action: #selector(captureScrollingUpAction), keyEquivalent: "4")
        scrollUpItem.keyEquivalentModifierMask = [.control, .shift]
        scrollUpItem.image = NSImage(systemSymbolName: "arrow.up.doc", accessibilityDescription: nil)
        menu.addItem(scrollUpItem)

        let delayedItem = NSMenuItem(title: "Delayed Screenshot (3s)", action: #selector(captureDelayedAction), keyEquivalent: "d")
        delayedItem.keyEquivalentModifierMask = [.control, .shift]
        delayedItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        menu.addItem(delayedItem)

        menu.addItem(NSMenuItem.separator())

        let ocrItem = NSMenuItem(title: "Recognize Text / QR Code", action: #selector(captureOCRAction), keyEquivalent: "o")
        ocrItem.keyEquivalentModifierMask = [.control, .shift]
        ocrItem.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: nil)
        menu.addItem(ocrItem)

        let clipboardItem = NSMenuItem(title: "Load From Clipboard", action: #selector(loadClipboardAction), keyEquivalent: "v")
        clipboardItem.keyEquivalentModifierMask = [.control, .shift]
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

        statusItem?.menu = menu
    }

    private func handlePostCapture(_ image: NSImage?) {
        guard let image = image else { return }

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

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
