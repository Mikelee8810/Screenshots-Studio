import Foundation
import Carbon.HIToolbox

/// Registers global hotkeys through the Carbon Event Manager.
/// This deliberately uses RegisterEventHotKey (not NSEvent global monitors / CGEventTap)
/// because it does NOT require Accessibility permission.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, action: CaptureAction)] = [:]
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x47545452 // 'GTTR'

    /// Called on the main thread when a hotkey fires.
    var onAction: ((CaptureAction) -> Void)?

    private init() {}

    func start() {
        installHandlerIfNeeded()
        reloadFromConfig()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard status == noErr else { return status }
            mgr.handleFired(id: hkID.id)
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    private func handleFired(id: UInt32) {
        guard let entry = registered[id] else { return }
        let action = entry.action
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }

    /// Unregister everything and re-register from the current Config.
    func reloadFromConfig() {
        unregisterAll()
        for action in CaptureAction.allCases {
            guard let spec = Config.shared.hotkeys[action], spec.enabled,
                  spec.keyCode != 0 || spec.modifiers != 0 else { continue }
            register(spec, for: action)
        }
    }

    @discardableResult
    private func register(_ spec: HotkeySpec, for action: CaptureAction) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            registered[id] = (ref, action)
            return true
        } else {
            NSLog("Screenshots: failed to register hotkey for \(action.rawValue) status=\(status)")
            return false
        }
    }

    private func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    /// Whether a candidate combo is already used by another action (used by the recorder UI).
    func conflictingAction(keyCode: UInt32, modifiers: UInt32, excluding: CaptureAction) -> CaptureAction? {
        for action in CaptureAction.allCases where action != excluding {
            if let s = Config.shared.hotkeys[action], s.enabled,
               s.keyCode == keyCode, s.modifiers == modifiers {
                return action
            }
        }
        return nil
    }
}
