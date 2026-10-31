import AppKit

/// Preferences: editable global hotkeys for every capture mode, plus after-capture behaviour,
/// save location, and toggles.
@MainActor
final class PreferencesWindowController: NSObject {
    private let window: NSWindow
    private let onChange: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveDirLabel = NSTextField(labelWithString: "")

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Screenshots Preferences"
        window.isReleasedWhenClosed = false
        build()
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func header(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(header("GLOBAL SHORTCUTS"))

        for action in CaptureAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 190).isActive = true

            let recorder = ShortcutRecorderButton(action: action, onChange: { [weak self] in
                self?.onChange()
                self?.statusLabel.stringValue = ""
            }, conflict: { [weak self] msg in
                self?.statusLabel.stringValue = msg
            })

            let clearBtn = NSButton(title: "Disable", target: self, action: #selector(disableAction(_:)))
            clearBtn.bezelStyle = .roundRect
            clearBtn.tag = CaptureAction.allCases.firstIndex(of: action) ?? 0

            let row = NSStackView(views: [label, recorder, clearBtn])
            row.orientation = .horizontal
            row.spacing = 8
            root.addArrangedSubview(row)
        }

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        root.addArrangedSubview(statusLabel)

        root.addArrangedSubview(spacer(8))
        root.addArrangedSubview(header("AFTER CAPTURE"))

        let afterPopup = NSPopUpButton()
        for a in AfterCaptureAction.allCases { afterPopup.addItem(withTitle: a.title) }
        afterPopup.selectItem(at: AfterCaptureAction.allCases.firstIndex(of: Config.shared.afterCapture) ?? 0)
        afterPopup.target = self
        afterPopup.action = #selector(afterCaptureChanged(_:))
        root.addArrangedSubview(afterPopup)

        let copyToggle = NSButton(checkboxWithTitle: "Always copy to clipboard on capture", target: self, action: #selector(copyToggleChanged(_:)))
        copyToggle.state = Config.shared.copyOnCapture ? .on : .off
        root.addArrangedSubview(copyToggle)

        let soundToggle = NSButton(checkboxWithTitle: "Play capture sound", target: self, action: #selector(soundToggleChanged(_:)))
        soundToggle.state = Config.shared.playSound ? .on : .off
        root.addArrangedSubview(soundToggle)

        root.addArrangedSubview(spacer(8))
        root.addArrangedSubview(header("SAVE LOCATION"))
        saveDirLabel.stringValue = Config.shared.saveDirectory.path
        saveDirLabel.lineBreakMode = .byTruncatingMiddle
        saveDirLabel.font = NSFont.systemFont(ofSize: 11)
        saveDirLabel.textColor = .secondaryLabelColor
        let changeBtn = NSButton(title: "Change…", target: self, action: #selector(changeSaveDir))
        changeBtn.bezelStyle = .roundRect
        let saveRow = NSStackView(views: [saveDirLabel, changeBtn])
        saveRow.orientation = .horizontal
        saveRow.spacing = 8
        saveDirLabel.translatesAutoresizingMaskIntoConstraints = false
        saveDirLabel.widthAnchor.constraint(equalToConstant: 320).isActive = true
        root.addArrangedSubview(saveRow)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        window.contentView = container
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    @objc private func disableAction(_ sender: NSButton) {
        let action = CaptureAction.allCases[sender.tag]
        Config.shared.setHotkey(.empty, for: action)
        onChange()
        // Refresh the recorder buttons by rebuilding.
        build()
    }

    @objc private func afterCaptureChanged(_ sender: NSPopUpButton) {
        Config.shared.afterCapture = AfterCaptureAction.allCases[sender.indexOfSelectedItem]
    }
    @objc private func copyToggleChanged(_ sender: NSButton) { Config.shared.copyOnCapture = sender.state == .on }
    @objc private func soundToggleChanged(_ sender: NSButton) { Config.shared.playSound = sender.state == .on }

    @objc private func changeSaveDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = Config.shared.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            Config.shared.saveDirectory = url
            saveDirLabel.stringValue = url.path
        }
    }
}
