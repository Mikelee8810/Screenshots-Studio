import AppKit

/// Owns all open editor windows (keeps them alive; releases on close).
@MainActor
final class EditorController {
    static let shared = EditorController()
    private var controllers: [EditorWindowController] = []
    private init() {}

    func open(_ captured: CapturedImage) {
        let wc = EditorWindowController(captured: captured)
        wc.onClose = { [weak self, weak wc] in
            self?.controllers.removeAll { $0 === wc }
        }
        controllers.append(wc)
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow()
    }

    func openImageFile(_ url: URL) -> Bool {
        guard let img = NSImage(contentsOf: url),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return false }
        let scale = (rep.pixelsWide > 0 && img.size.width > 0) ? CGFloat(rep.pixelsWide) / img.size.width : 1
        open(CapturedImage(cgImage: cg, scale: scale, originPoint: nil))
        return true
    }
}
