import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var prefs: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        HotkeyManager.shared.onAction = { action in
            CaptureController.shared.perform(action)
        }
        HotkeyManager.shared.start()

        // Support `--edit <path>` or direct image path to open the editor directly.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--edit"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            if !EditorController.shared.openImageFile(url) {
                NSLog("Screenshots: could not open image at \(url.path)")
            }
        } else {
            for arg in args.dropFirst() {
                if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg) {
                    let url = URL(fileURLWithPath: arg)
                    _ = EditorController.shared.openImageFile(url)
                    break
                }
            }
        }

        // Debug: `--show-overlay area|window` triggers a capture overlay so it can be screenshotted.
        if let i = args.firstIndex(of: "--show-overlay"), i + 1 < args.count {
            let mode = args[i + 1]
            CGWarpMouseCursorPosition(CGPoint(x: 700, y: 450))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                CaptureController.shared.perform(mode == "window" ? .window : .area)
            }
        }

        // Debug: `--show-prefs` opens Preferences on launch.
        if args.contains("--show-prefs") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.openPreferences() }
        }

        // Debug: `--pin <path>` pins an image on launch.
        if let i = args.firstIndex(of: "--pin"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            if let img = NSImage(contentsOf: url) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApp.activate(ignoringOtherApps: true)
                    PinController.shared.pin(img, at: nil)
                }
            }
        }
    }

    // MARK: Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Screenshots") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "✂"
            }
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: #selector(captureMenuClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let spec = Config.shared.hotkeys[action], spec.enabled {
                item.title = "\(action.menuTitle)\t\(KeyCodes.displayString(spec))"
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let prefItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Screenshots", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func captureMenuClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        CaptureController.shared.perform(action)
    }

    @objc private func openPreferences() {
        if prefs == nil {
            prefs = PreferencesWindowController { [weak self] in
                HotkeyManager.shared.reloadFromConfig()
                self?.rebuildMenu()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        prefs?.show()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        return EditorController.shared.openImageFile(URL(fileURLWithPath: filename))
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for file in filenames {
            _ = EditorController.shared.openImageFile(URL(fileURLWithPath: file))
        }
    }
}
