import AppKit
import ScreenCaptureKit

/// Orchestrates all capture flows and routes finished captures to the configured after-capture action.
@MainActor
final class CaptureController {
    static let shared = CaptureController()
    private init() {}

    // MARK: Entry points

    func perform(_ action: CaptureAction) {
        // Don't start a new capture while an overlay is already up.
        if AreaSelectionController.shared.isActive || WindowPickerController.shared.isActive { return }
        switch action {
        case .fullscreen: captureFullscreen()
        case .area:   AreaSelectionController.shared.begin { [weak self] in self?.handle($0) }
        case .window: WindowPickerController.shared.begin { [weak self] in self?.handle($0) }
        case .fixed:  captureFixed()
        }
    }

    private func captureFullscreen() {
        Task { @MainActor in
            do {
                let content = try await ScreenCapture.shareableContent()
                let display = displayUnderCursor(content) ?? content.displays.first
                guard let display else { throw CaptureError.noDisplay }
                let cg = try await ScreenCapture.captureDisplay(display)
                let scale = ScreenCapture.scale(for: display)
                let origin = ScreenCapture.nsScreen(for: display).map { Coordinates.cgOrigin(of: $0) } ?? .zero
                handle(CapturedImage(cgImage: cg, scale: scale, originPoint: origin))
            } catch { present(error: error) }
        }
    }

    private func captureFixed() {
        guard let rect = Config.shared.fixedRect else {
            HUD.show("No fixed region set — capture an area first")
            return
        }
        Task { @MainActor in
            do { handle(try await captureGlobalRect(rect)) }
            catch { present(error: error) }
        }
    }

    /// Capture the whole main (or first) display. Used by the CLI.
    func grabFullDisplay() async throws -> CapturedImage {
        let content = try await ScreenCapture.shareableContent()
        let display = displayUnderCursor(content) ?? content.displays.first
        guard let display else { throw CaptureError.noDisplay }
        let cg = try await ScreenCapture.captureDisplay(display)
        let scale = ScreenCapture.scale(for: display)
        let origin = ScreenCapture.nsScreen(for: display).map { Coordinates.cgOrigin(of: $0) } ?? .zero
        return CapturedImage(cgImage: cg, scale: scale, originPoint: origin)
    }

    /// Capture an arbitrary global CG (top-left) rectangle. Used by fixed-region + CLI.
    func captureGlobalRect(_ rect: CGRect) async throws -> CapturedImage {
        let content = try await ScreenCapture.shareableContent()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = Coordinates.screen(forCGTopLeft: center) ?? NSScreen.main,
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == CGDirectDisplayID(num.uint32Value) })
        else { throw CaptureError.noDisplay }
        let full = try await ScreenCapture.captureDisplay(display)
        let scale = ScreenCapture.scale(for: display)
        let origin = Coordinates.cgOrigin(of: screen)
        let local = CGRect(x: rect.minX - origin.x, y: rect.minY - origin.y, width: rect.width, height: rect.height)
        guard let cropped = ScreenCapture.crop(full, toPointRect: local, scale: scale) else {
            throw CaptureError.failed("Selected rectangle is outside the screen.")
        }
        return CapturedImage(cgImage: cropped, scale: scale, originPoint: rect.origin)
    }

    private func displayUnderCursor(_ content: SCShareableContent) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return content.displays.first(where: { $0.displayID == CGDirectDisplayID(num.uint32Value) })
    }

    // MARK: After-capture routing

    func handle(_ captured: CapturedImage?) {
        guard let captured else { return } // cancelled
        if Config.shared.playSound { NSSound(named: "Grab")?.play() }
        if Config.shared.copyOnCapture { copyToPasteboard(captured.nsImage) }

        switch Config.shared.afterCapture {
        case .copyToClipboard:
            copyToPasteboard(captured.nsImage)
            HUD.show("Copied to clipboard")
        case .saveToDisk:
            if let url = save(captured) { HUD.show("Saved to \(url.lastPathComponent)") }
        case .openEditor:
            EditorController.shared.open(captured)
        }
    }

    // MARK: Output helpers

    func copyToPasteboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    @discardableResult
    func save(_ captured: CapturedImage) -> URL? {
        guard let data = captured.pngData() else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(df.string(from: Date())).png"
        let dir = Config.shared.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do { try data.write(to: url); return url }
        catch { present(error: CaptureError.failed("Could not save: \(error.localizedDescription)")); return nil }
    }

    // MARK: Errors

    func present(error: Error) {
        NSLog("Screenshots capture error: \(error.localizedDescription)")
        let alert = NSAlert()
        alert.messageText = "Screenshots"
        alert.informativeText = (error as? CaptureError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        if case CaptureError.noPermission = error {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
