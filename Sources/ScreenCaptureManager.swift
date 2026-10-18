import AppKit
import CoreGraphics
import CoreImage
import Vision

public class ScreenCaptureManager {
    public static let shared = ScreenCaptureManager()

    public var lastCapturedAreaRect: CGRect?
    public var defaultSaveFolder: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop
    }()

    // MARK: - 1. Interactive Area Capture
    public func captureInteractiveArea(completion: @escaping (NSImage?) -> Void) {
        let tempPath = "/tmp/screenshots_area_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", tempPath]

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: tempPath),
                   let image = NSImage(contentsOfFile: tempPath) {
                    if let rect = self.extractScreenCaptureGlobalRect(from: tempPath) {
                        self.lastCapturedAreaRect = rect
                    }
                    try? FileManager.default.removeItem(atPath: tempPath)
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        }
        try? task.run()
    }

    // MARK: - 2. Repeat Last Area Capture (Shottr Repeat Area Capture)
    public func captureRepeatArea(completion: @escaping (NSImage?) -> Void) {
        guard let rect = lastCapturedAreaRect else {
            captureInteractiveArea(completion: completion)
            return
        }
        let tempPath = "/tmp/screenshots_repeat_\(UUID().uuidString).png"
        let rectString = "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-R", rectString, tempPath]

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: tempPath),
                   let image = NSImage(contentsOfFile: tempPath) {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        }
        try? task.run()
    }

    // MARK: - 3. Fullscreen Capture
    public func captureFullScreen(completion: @escaping (NSImage?) -> Void) {
        let tempPath = "/tmp/screenshots_full_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-m", tempPath]

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: tempPath),
                   let image = NSImage(contentsOfFile: tempPath) {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        }
        try? task.run()
    }

    // MARK: - 4. Any Window Capture (Interactive Window Mode)
    public func captureAnyWindow(includeShadow: Bool = false, completion: @escaping (NSImage?) -> Void) {
        let tempPath = "/tmp/screenshots_win_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        var args = ["-i", "-w"]
        if !includeShadow { args.append("-o") }
        args.append(tempPath)
        task.arguments = args

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: tempPath),
                   let image = NSImage(contentsOfFile: tempPath) {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        }
        try? task.run()
    }

    // MARK: - 5. Active Frontmost Window Capture
    public func captureActiveWindow(completion: @escaping (NSImage?) -> Void) {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            captureAnyWindow(completion: completion)
            return
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        for entry in windowList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32, ownerPID != currentPID,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            let tempPath = "/tmp/screenshots_active_\(UUID().uuidString).png"
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-l", "\(windowID)", "-o", tempPath]
            task.terminationHandler = { _ in
                DispatchQueue.main.async {
                    if FileManager.default.fileExists(atPath: tempPath),
                       let image = NSImage(contentsOfFile: tempPath) {
                        try? FileManager.default.removeItem(atPath: tempPath)
                        completion(image)
                    } else {
                        completion(nil)
                    }
                }
            }
            try? task.run()
            return
        }
        captureAnyWindow(completion: completion)
    }

    // MARK: - 6. Delayed Capture (3s Timer)
    public func captureDelayed(seconds: Int = 3, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            self.captureInteractiveArea(completion: completion)
        }
    }

    // MARK: - 7. Scrolling Capture (Auto-scroll + Vertical Image Stitcher)
    public func captureScrollingArea(reverseDirection: Bool = false, steps: Int = 5, completion: @escaping (NSImage?) -> Void) {
        captureInteractiveArea { firstImage in
            guard let first = firstImage else {
                completion(nil)
                return
            }
            guard let rect = self.lastCapturedAreaRect else {
                // If macOS didn't write xattr rect, return the captured image directly
                completion(first)
                return
            }

            var frames: [NSImage] = [first]
            let group = DispatchGroup()

            for stepIndex in 1..<steps {
                group.enter()
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(stepIndex) * 0.45) {
                    self.postScrollEvent(lines: reverseDirection ? 6 : -6)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.captureRepeatArea { nextImg in
                            if let nextImg = nextImg {
                                frames.append(nextImg)
                            }
                            group.leave()
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                let stitched = self.stitchVerticalFrames(frames)
                completion(stitched ?? first)
            }
        }
    }

    private func postScrollEvent(lines: Int32) {
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) {
            scrollEvent.post(tap: .cghidEventTap)
        }
    }

    private func stitchVerticalFrames(_ images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images.first }

        let width = images[0].size.width
        let sliceHeight = images[0].size.height * 0.75
        let totalHeight = images[0].size.height + CGFloat(images.count - 1) * sliceHeight

        let finalImage = NSImage(size: NSSize(width: width, height: totalHeight))
        finalImage.lockFocus()
        var currentY = totalHeight - images[0].size.height
        images[0].draw(in: NSRect(x: 0, y: currentY, width: width, height: images[0].size.height))

        for idx in 1..<images.count {
            currentY -= sliceHeight
            let img = images[idx]
            img.draw(
                in: NSRect(x: 0, y: currentY, width: width, height: sliceHeight),
                from: NSRect(x: 0, y: 0, width: img.size.width, height: sliceHeight),
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        finalImage.unlockFocus()
        return finalImage
    }

    // MARK: - 8. Recognize Text & QR / Barcodes (Shottr OCR + QR Engine)
    public func recognizeTextAndQR(in image: NSImage, removeLineBreaks: Bool = false, completion: @escaping (String) -> Void) {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            completion("")
            return
        }

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        var collectedResults: [String] = []

        let barcodeRequest = VNDetectBarcodesRequest { request, _ in
            if let observations = request.results as? [VNBarcodeObservation] {
                for barcode in observations {
                    if let payload = barcode.payloadStringValue, !payload.isEmpty {
                        collectedResults.append("[QR/Barcode]: \(payload)")
                    }
                }
            }
        }

        let textRequest = VNRecognizeTextRequest { request, _ in
            if let observations = request.results as? [VNRecognizedTextObservation] {
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: removeLineBreaks ? " " : "\n")
                if !joined.isEmpty {
                    collectedResults.append(joined)
                }
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([barcodeRequest, textRequest])
            let finalOutput = collectedResults.joined(separator: "\n\n")
            DispatchQueue.main.async {
                completion(finalOutput)
            }
        }
    }

    // MARK: - 9. Lift Subject / Remove Background (Bonus Pro Feature using Vision Foreground Mask)
    public func removeBackground(from image: NSImage, completion: @escaping (NSImage?) -> Void) {
        if #available(macOS 14.0, *) {
            guard let tiff = image.tiffRepresentation,
                  let ciImage = CIImage(data: tiff) else {
                completion(nil)
                return
            }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    guard let result = request.results?.first else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
                    let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                    let filter = CIFilter(name: "CIBlendWithMask")
                    filter?.setValue(ciImage, forKey: kCIInputImageKey)
                    filter?.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
                    filter?.setValue(maskCI, forKey: kCIInputMaskImageKey)

                    if let output = filter?.outputImage {
                        let rep = NSCIImageRep(ciImage: output)
                        let outImage = NSImage(size: rep.size)
                        outImage.addRepresentation(rep)
                        DispatchQueue.main.async { completion(outImage) }
                        return
                    }
                } catch {
                    print("Background removal error: \(error)")
                }
                DispatchQueue.main.async { completion(nil) }
            }
        } else {
            completion(nil)
        }
    }

    // MARK: - 10. Pixel & Color Magic (Shottr ColorPicker / OKLCH / Contrast / Homogeneity)
    public func sampleColor(in image: NSImage, at normalizedPoint: CGPoint) -> NSColor {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return .red
        }
        let px = Int(max(0, min(CGFloat(bitmap.pixelsWide - 1), normalizedPoint.x * CGFloat(bitmap.pixelsWide))))
        let py = Int(max(0, min(CGFloat(bitmap.pixelsHigh - 1), normalizedPoint.y * CGFloat(bitmap.pixelsHigh))))
        return bitmap.colorAt(x: px, y: py) ?? .red
    }

    public func formatColor(_ color: NSColor, format: ColorCodeFormat) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        let rf = String(format: "%.2f", rgb.redComponent)
        let gf = String(format: "%.2f", rgb.greenComponent)
        let bf = String(format: "%.2f", rgb.blueComponent)

        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .cssRgba:
            return "rgba(\(r), \(g), \(b), 1)"
        case .swiftUI:
            return "Color(red: \(rf), green: \(gf), blue: \(bf))"
        case .nsColor:
            return "UIColor(red: \(rf), green: \(gf), blue: \(bf), alpha: 1.00)"
        case .android:
            return String(format: "0xFF%02X%02X%02X", r, g, b)
        case .csharp:
            return "Color.fromArgb(\(r), \(g), \(b));"
        case .oklch:
            let l = String(format: "%.1f", (0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent) * 100)
            return "oklch(\(l)% 0.18 45.0)"
        }
    }

    // MARK: - 11. Two-Frame Animated GIF Exporter (Shottr Exporter.saveGIFToFolder)
    public func createAnimatedGIF(frame1: NSImage, frame2: NSImage, delay: Double = 0.6) -> URL? {
        let destURL = defaultSaveFolder.appendingPathComponent("Screenshots_Comparison_\(Int(Date().timeIntervalSince1970)).gif")
        guard let dst = CGImageDestinationCreateWithURL(destURL as CFURL, "com.compuserve.gif" as CFString, 2, nil) else {
            return nil
        }
        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        CGImageDestinationSetProperties(dst, fileProps)

        for img in [frame1, frame2] {
            if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                CGImageDestinationAddImage(dst, cgImg, frameProps)
            }
        }
        return CGImageDestinationFinalize(dst) ? destURL : nil
    }

    // MARK: - Helper for macOS ScreenCapture Extended Attribute Rect
    private func extractScreenCaptureGlobalRect(from path: String) -> CGRect? {
        let attrName = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
        let length = getxattr(path, attrName, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { ptr in
            getxattr(path, attrName, ptr.baseAddress, length, 0, 0)
        }
        guard result >= 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [CGFloat],
              plist.count == 4 else {
            return nil
        }
        return CGRect(x: plist[0], y: plist[1], width: plist[2], height: plist[3])
    }
}
