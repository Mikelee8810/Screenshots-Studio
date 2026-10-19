import AppKit
import ApplicationServices
import CoreGraphics
import CoreServices
import Combine

// MARK: - Dedicated macOS Permission Manager (Screen Recording, Accessibility & Automation)

public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public var hasScreenRecording: Bool = false
    @Published public var hasAccessibility: Bool = false
    @Published public var hasAutomation: Bool = false

    private init() {
        refresh()
    }

    public func refresh() {
        hasScreenRecording = checkScreenRecording()
        hasAccessibility = checkAccessibility()
        hasAutomation = checkAutomation()
    }

    // MARK: - 1. Screen Recording
    public func checkScreenRecording() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    public func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - 2. Accessibility
    public func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - 3. Automation (Apple Events -> System Events & Other Apps)
    public func checkAutomation() -> Bool {
        var target = AEAddressDesc()
        let bundleId = "com.apple.systemevents"
        _ = bundleId.withCString { cstr in
            AECreateDesc(typeApplicationBundleID, cstr, strlen(cstr), &target)
        }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        AEDisposeDesc(&target)
        return status == noErr
    }

    public func requestAutomation() {
        // Trigger Apple Event system prompt via AEDeterminePermissionToAutomateTarget
        var target = AEAddressDesc()
        let bundleId = "com.apple.systemevents"
        _ = bundleId.withCString { cstr in
            AECreateDesc(typeApplicationBundleID, cstr, strlen(cstr), &target)
        }
        _ = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), true)
        AEDisposeDesc(&target)

        // Execute AppleScript to register with macOS TCC Automation database
        let scriptSource = "tell application \"System Events\" to return name of first application process whose frontmost is true"
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - 4. Request All Permissions
    public func requestAllPermissions() {
        // Accessibility prompt
        if !checkAccessibility() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // Automation prompt & registration
        if !checkAutomation() {
            var target = AEAddressDesc()
            let bundleId = "com.apple.systemevents"
            _ = bundleId.withCString { cstr in
                AECreateDesc(typeApplicationBundleID, cstr, strlen(cstr), &target)
            }
            _ = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), true)
            AEDisposeDesc(&target)

            let scriptSource = "tell application \"System Events\" to return name of first application process whose frontmost is true"
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&error)
            }
        }

        // Screen recording prompt
        if !checkScreenRecording() {
            CGRequestScreenCaptureAccess()
        }

        refresh()
    }
}
