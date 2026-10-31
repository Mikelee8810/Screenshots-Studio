import AppKit
import Carbon.HIToolbox

/// A button that records a global-hotkey combination. Click it, then press the desired combo.
/// Esc cancels; Delete/Backspace clears the shortcut.
final class ShortcutRecorderButton: NSButton {
    private let captureAction: CaptureAction
    private let onChange: () -> Void
    private var recording = false
    private var conflictMessage: ((String) -> Void)?

    init(action: CaptureAction, onChange: @escaping () -> Void, conflict: ((String) -> Void)? = nil) {
        self.captureAction = action
        self.onChange = onChange
        self.conflictMessage = conflict
        super.init(frame: .zero)
        bezelStyle = .roundRect
        setButtonType(.momentaryPushIn)
        self.target = self
        self.action = #selector(beginRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    private func refresh() {
        if recording {
            title = "Type shortcut…"
        } else if let spec = Config.shared.hotkeys[captureAction], spec.enabled, spec.keyCode != 0 {
            title = KeyCodes.displayString(spec)
        } else {
            title = "Click to record"
        }
    }

    @objc private func beginRecording() {
        recording = true
        window?.makeFirstResponder(self)
        refresh()
    }

    private func stop() {
        recording = false
        if window?.firstResponder == self { window?.makeFirstResponder(nil) }
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refresh()
        return super.resignFirstResponder()
    }

    override func flagsChanged(with event: NSEvent) {
        if recording {
            let mods = KeyCodes.carbonModifiers(from: event.modifierFlags)
            title = mods == 0 ? "Type shortcut…" : KeyCodes.modifierString(mods) + "…"
        }
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let code = event.keyCode

        if Int(code) == kVK_Escape { stop(); return }
        if Int(code) == kVK_Delete || Int(code) == kVK_ForwardDelete {
            Config.shared.setHotkey(.empty, for: captureAction)
            onChange(); stop(); return
        }
        if KeyCodes.isModifierKey(code) { return } // wait for the non-modifier key

        let mods = KeyCodes.carbonModifiers(from: event.modifierFlags)
        let hasRequiredModifier = mods & UInt32(cmdKey | controlKey | optionKey) != 0
        guard hasRequiredModifier else { NSSound.beep(); return }

        if let conflict = HotkeyManager.shared.conflictingAction(keyCode: UInt32(code), modifiers: mods, excluding: captureAction) {
            NSSound.beep()
            conflictMessage?("Already used by “\(conflict.title)”")
            return
        }
        Config.shared.setHotkey(HotkeySpec(keyCode: UInt32(code), modifiers: mods, enabled: true), for: captureAction)
        onChange()
        stop()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While recording, swallow key equivalents (e.g. ⌘Q) so we can record them.
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
