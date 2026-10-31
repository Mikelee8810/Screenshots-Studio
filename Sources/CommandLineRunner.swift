import AppKit
import ScreenCaptureKit

/// Headless one-shot commands used for scripting and automated verification.
/// Interactive modes (area/window selection, the editor) run in normal GUI mode instead.
enum CommandLineRunner {

    static func run(_ args: [String]) -> Never {
        if args.first == "--version" { print("Screenshots 1.0"); exit(0) }
        if args.first == "--help" { printUsage(); exit(0) }
        pump { await execute(args) }
    }

    private final class Box { var code: Int32 = 0 }

    private static func pump(_ body: @escaping () async -> Int32) -> Never {
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        Task.detached { box.code = await body(); sem.signal() }
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        exit(box.code)
    }

    private static func execute(_ args: [String]) async -> Int32 {
        do {
            switch args[0] {
            case "--list-windows":
                let content = try await ScreenCapture.shareableContent()
                for w in content.windows where w.isOnScreen && w.frame.width > 20 {
                    let app = w.owningApplication?.applicationName ?? "?"
                    let f = w.frame
                    print("\(w.windowID)\t\(app)\t\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))\t\(w.title ?? "")")
                }
                return 0

            case "--capture":
                let mode = value(args, after: "--capture") ?? "full"
                guard mode == "full" else {
                    err("Only 'full' is supported headlessly. Use --capture-rect, or the GUI for area/window.")
                    return 2
                }
                let captured = try await CaptureController.shared.grabFullDisplay()
                return writeOut(captured, value(args, after: "--out"))

            case "--capture-rect":
                guard let spec = value(args, after: "--capture-rect"), let rect = parseRect(spec) else {
                    err("Usage: --capture-rect X,Y,W,H [--out PATH]"); return 2
                }
                let captured = try await CaptureController.shared.captureGlobalRect(rect)
                return writeOut(captured, value(args, after: "--out"))

            case "--selftest":
                let out = value(args, after: "--selftest") ?? Config.shared.saveDirectory.appendingPathComponent("Screenshots-selftest.png").path
                let source: CGImage
                let scale: CGFloat
                if let src = value(args, after: "--src"), let loaded = loadCGImage(src) {
                    source = loaded.0; scale = loaded.1
                } else {
                    let cap = try await CaptureController.shared.grabFullDisplay()
                    source = cap.cgImage; scale = cap.scale
                }
                let pointSize = NSSize(width: CGFloat(source.width) / scale, height: CGFloat(source.height) / scale)
                let data: Data? = await MainActor.run {
                    let anns = AnnotationRenderer.demoAnnotations(pointSize: pointSize)
                    return AnnotationRenderer.png(source: source, captureScale: scale, annotations: anns)
                }
                guard let data = data else { err("selftest render failed"); return 1 }
                let url = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
                print(url.path)
                return 0

            default:
                err("Unknown command: \(args[0])"); printUsage(); return 2
            }
        } catch {
            err((error as? CaptureError)?.errorDescription ?? error.localizedDescription)
            return 1
        }
    }

    // MARK: helpers

    private static func value(_ args: [String], after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.hasPrefix("--") ? nil : v
    }

    private static func loadCGImage(_ path: String) -> (CGImage, CGFloat)? {
        let p = (path as NSString).expandingTildeInPath
        guard let img = NSImage(contentsOfFile: p), let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { return nil }
        let scale = img.size.width > 0 ? CGFloat(rep.pixelsWide) / img.size.width : 1
        return (cg, max(1, scale))
    }

    private static func parseRect(_ s: String) -> CGRect? {
        let parts = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    private static func writeOut(_ captured: CapturedImage, _ out: String?) -> Int32 {
        guard let data = captured.pngData() else { err("Failed to encode PNG"); return 1 }
        let url: URL
        if let out = out {
            url = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        } else {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            url = Config.shared.saveDirectory.appendingPathComponent("Screenshot \(df.string(from: Date())).png")
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            print(url.path)
            return 0
        } catch {
            err("Write failed: \(error.localizedDescription)"); return 1
        }
    }

    private static func err(_ m: String) {
        FileHandle.standardError.write(("gottr: " + m + "\n").data(using: .utf8)!)
    }

    private static func printUsage() {
        let usage = """
        Screenshots — usage:
          (no args)                      run as menu-bar app
          --edit PATH                    open the editor with an image (GUI)
          --capture full [--out PATH]    capture the display under the cursor
          --capture-rect X,Y,W,H [--out] capture a global rectangle (top-left origin)
          --list-windows                 list on-screen windows (id, app, frame, title)
          --version
        """
        print(usage)
    }
}
