import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Customizable global shortcut model

enum HotkeyAction: String, CaseIterable, Identifiable {
    case fullscreen, area, scrollDown, scrollUp, anyWindow, activeWindow, repeatArea, ocr, delayed, record

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullscreen: return "Fullscreen Screenshot"
        case .area: return "Area Screenshot"
        case .scrollDown: return "Scrolling Capture (Down)"
        case .scrollUp: return "Reverse Scrolling Capture (Up)"
        case .anyWindow: return "Capture Any Window"
        case .activeWindow: return "Capture Active Window"
        case .repeatArea: return "Repeat Last Area Capture"
        case .ocr: return "Recognize Text / QR (OCR)"
        case .delayed: return "Delayed Screenshot (3s)"
        case .record: return "Start / Stop Screen Recording"
        }
    }

    var defaultBinding: HotkeyBinding {
        let mods = controlKey | shiftKey
        switch self {
        case .fullscreen: return HotkeyBinding(keyCode: kVK_ANSI_1, mods: mods, label: "1")
        case .area: return HotkeyBinding(keyCode: kVK_ANSI_2, mods: mods, label: "2")
        case .scrollDown: return HotkeyBinding(keyCode: kVK_ANSI_3, mods: mods, label: "3")
        case .scrollUp: return HotkeyBinding(keyCode: kVK_ANSI_4, mods: mods, label: "4")
        case .anyWindow: return HotkeyBinding(keyCode: kVK_ANSI_W, mods: mods, label: "W")
        case .activeWindow: return HotkeyBinding(keyCode: kVK_ANSI_A, mods: mods, label: "A")
        case .repeatArea: return HotkeyBinding(keyCode: kVK_ANSI_R, mods: mods, label: "R")
        case .ocr: return HotkeyBinding(keyCode: kVK_ANSI_O, mods: mods, label: "O")
        case .delayed: return HotkeyBinding(keyCode: kVK_ANSI_D, mods: mods, label: "D")
        case .record: return HotkeyBinding(keyCode: kVK_ANSI_5, mods: mods, label: "5")
        }
    }
}

struct HotkeyBinding: Equatable {
    var keyCode: Int
    var mods: Int      // Carbon modifier mask
    var label: String  // Key character, e.g. "2"

    var display: String {
        var s = ""
        if mods & controlKey != 0 { s += "⌃" }
        if mods & optionKey != 0 { s += "⌥" }
        if mods & shiftKey != 0 { s += "⇧" }
        if mods & cmdKey != 0 { s += "⌘" }
        return s + " " + label.uppercased()
    }

    var menuMask: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if mods & controlKey != 0 { f.insert(.control) }
        if mods & optionKey != 0 { f.insert(.option) }
        if mods & shiftKey != 0 { f.insert(.shift) }
        if mods & cmdKey != 0 { f.insert(.command) }
        return f
    }

    var stored: String { "\(keyCode),\(mods),\(label)" }

    init(keyCode: Int, mods: Int, label: String) {
        self.keyCode = keyCode
        self.mods = mods
        self.label = label
    }

    init?(stored: String) {
        let parts = stored.split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count == 3, let k = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        self.init(keyCode: k, mods: m, label: parts[2])
    }
}

final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    static let changedNotification = Notification.Name("ScreenshotsHotkeysChanged")

    @Published var bindings: [HotkeyAction: HotkeyBinding] = [:]

    private init() {
        for action in HotkeyAction.allCases {
            if let raw = UserDefaults.standard.string(forKey: "hotkey.\(action.rawValue)"),
               let b = HotkeyBinding(stored: raw) {
                bindings[action] = b
            } else {
                bindings[action] = action.defaultBinding
            }
        }
    }

    func set(_ action: HotkeyAction, to binding: HotkeyBinding) {
        // Free the combo if another action already uses it.
        for (other, b) in bindings where other != action && b.keyCode == binding.keyCode && b.mods == binding.mods {
            bindings[other] = nil
            UserDefaults.standard.removeObject(forKey: "hotkey.\(other.rawValue)")
        }
        bindings[action] = binding
        UserDefaults.standard.set(binding.stored, forKey: "hotkey.\(action.rawValue)")
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func resetAll() {
        for action in HotkeyAction.allCases {
            UserDefaults.standard.removeObject(forKey: "hotkey.\(action.rawValue)")
            bindings[action] = action.defaultBinding
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }
}

// MARK: - Key recorder UI

final class ShortcutRecorderModel: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?

    func toggle(onCapture: @escaping (HotkeyBinding) -> Void) {
        if isRecording { stop(); return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // Esc cancels
                self.stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods = 0
            if flags.contains(.control) { mods |= controlKey }
            if flags.contains(.option) { mods |= optionKey }
            if flags.contains(.shift) { mods |= shiftKey }
            if flags.contains(.command) { mods |= cmdKey }
            guard mods != 0, let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
                NSSound.beep() // global shortcuts need at least one modifier key
                return nil
            }
            onCapture(HotkeyBinding(keyCode: Int(event.keyCode), mods: mods, label: String(chars.prefix(1))))
            self.stop()
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        isRecording = false
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

struct ShortcutRecorderRow: View {
    let action: HotkeyAction
    @ObservedObject private var store = ShortcutStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var recorder = ShortcutRecorderModel()

    var body: some View {
        HStack {
            Text(action.title)
                .font(.system(size: 12.5))
                .foregroundColor(StudioTheme.textPrimary)
            Spacer()
            Button(action: {
                recorder.toggle { binding in store.set(action, to: binding) }
            }) {
                Text(recorder.isRecording ? "Press keys… (Esc cancels)" : (store.bindings[action]?.display ?? "Not set"))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(recorder.isRecording ? .white : StudioTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(recorder.isRecording ? StudioTheme.accent : StudioTheme.bgCanvas)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Click, then press the new key combination")
        }
    }
}
