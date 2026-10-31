import Foundation
import Carbon.HIToolbox

/// A global-hotkey key combination expressed in Carbon terms.
struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32      // Carbon/HIToolbox virtual key code (kVK_*)
    var modifiers: UInt32    // Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey)
    var enabled: Bool

    static let empty = HotkeySpec(keyCode: 0, modifiers: 0, enabled: false)
}

/// The distinct things a hotkey (or menu item) can trigger.
enum CaptureAction: String, CaseIterable, Codable {
    case area
    case window
    case fixed        // re-capture the last/remembered rectangle instantly
    case fullscreen

    var title: String {
        switch self {
        case .area: return "Capture Area"
        case .window: return "Capture Window"
        case .fixed: return "Capture Fixed Region"
        case .fullscreen: return "Capture Fullscreen"
        }
    }

    var menuTitle: String { title }

    /// Sensible, system-conflict-free defaults (macOS reserves ⌘⇧3/4/5/6).
    var defaultHotkey: HotkeySpec {
        switch self {
        case .area:       return HotkeySpec(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        case .window:     return HotkeySpec(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        case .fixed:      return HotkeySpec(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        case .fullscreen: return HotkeySpec(keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        }
    }
}

/// What happens immediately after a capture completes.
enum AfterCaptureAction: String, CaseIterable, Codable {
    case openEditor
    case copyToClipboard
    case saveToDisk

    var title: String {
        switch self {
        case .openEditor: return "Open in Editor"
        case .copyToClipboard: return "Copy to Clipboard"
        case .saveToDisk: return "Save to Disk"
        }
    }
}

/// Persistent user settings, JSON-backed in UserDefaults.
final class Config {
    static let shared = Config()

    private let defaults = UserDefaults.standard
    private let hotkeysKey = "gottr.hotkeys.v1"
    private let afterCaptureKey = "gottr.afterCapture.v1"
    private let saveDirKey = "gottr.saveDir.v1"
    private let fixedRectKey = "gottr.fixedRect.v1"
    private let copyOnCaptureKey = "gottr.copyOnCapture.v1"
    private let playSoundKey = "gottr.playSound.v1"

    private(set) var hotkeys: [CaptureAction: HotkeySpec]

    var afterCapture: AfterCaptureAction {
        didSet { defaults.set(afterCapture.rawValue, forKey: afterCaptureKey) }
    }

    /// Also copy to the clipboard whenever a capture is taken (in addition to the after-capture action).
    var copyOnCapture: Bool {
        didSet { defaults.set(copyOnCapture, forKey: copyOnCaptureKey) }
    }

    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: playSoundKey) }
    }

    /// Directory screenshots are saved to (defaults to ~/Desktop).
    var saveDirectory: URL {
        didSet { defaults.set(saveDirectory.path, forKey: saveDirKey) }
    }

    /// The remembered rectangle for the "fixed region" repeat capture (in global screen points, top-left origin).
    var fixedRect: CGRect? {
        didSet {
            if let r = fixedRect {
                defaults.set([r.origin.x, r.origin.y, r.size.width, r.size.height], forKey: fixedRectKey)
            } else {
                defaults.removeObject(forKey: fixedRectKey)
            }
        }
    }

    private init() {
        // Hotkeys
        var loaded: [CaptureAction: HotkeySpec] = [:]
        if let data = defaults.data(forKey: hotkeysKey),
           let decoded = try? JSONDecoder().decode([String: HotkeySpec].self, from: data) {
            for (k, v) in decoded {
                if let action = CaptureAction(rawValue: k) { loaded[action] = v }
            }
        }
        for action in CaptureAction.allCases where loaded[action] == nil {
            loaded[action] = action.defaultHotkey
        }
        hotkeys = loaded

        // After-capture action
        afterCapture = AfterCaptureAction(rawValue: defaults.string(forKey: afterCaptureKey) ?? "")
            ?? .openEditor

        copyOnCapture = defaults.object(forKey: copyOnCaptureKey) as? Bool ?? true
        playSound = defaults.object(forKey: playSoundKey) as? Bool ?? true

        if let path = defaults.string(forKey: saveDirKey) {
            saveDirectory = URL(fileURLWithPath: path)
        } else {
            saveDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        }

        if let arr = defaults.array(forKey: fixedRectKey) as? [CGFloat], arr.count == 4 {
            fixedRect = CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
        }
    }

    func setHotkey(_ spec: HotkeySpec, for action: CaptureAction) {
        hotkeys[action] = spec
        persistHotkeys()
    }

    private func persistHotkeys() {
        var dict: [String: HotkeySpec] = [:]
        for (k, v) in hotkeys { dict[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: hotkeysKey)
        }
    }
}
