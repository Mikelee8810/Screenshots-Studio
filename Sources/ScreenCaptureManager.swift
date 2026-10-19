import AppKit
import CoreGraphics
import CoreImage
import Vision
import ScreenCaptureKit

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

    // MARK: - 2. Repeat Last Area Capture (Instant In-Memory ScreenCaptureKit Engine)
    public func captureRegionDirect(rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        if #available(macOS 14.0, *) {
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    guard let display = content.displays.first else { throw NSError(domain: "SCK", code: -1) }
                    let scale = NSScreen.main?.backingScaleFactor ?? 2.0

                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.sourceRect = rect
                    config.width = max(1, Int(rect.width * scale))
                    config.height = max(1, Int(rect.height * scale))
                    config.showsCursor = false

                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let img = NSImage(cgImage: cgImage, size: rect.size)
                    DispatchQueue.main.async { completion(img) }
                    return
                } catch {
                    self.captureRegionFallback(rect: rect, completion: completion)
                }
            }
        } else {
            captureRegionFallback(rect: rect, completion: completion)
        }
    }

    private func captureRegionFallback(rect: CGRect, completion: @escaping (NSImage?) -> Void) {
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

    public func captureRepeatArea(completion: @escaping (NSImage?) -> Void) {
        guard let rect = lastCapturedAreaRect else {
            captureInteractiveArea(completion: completion)
            return
        }
        captureRegionDirect(rect: rect, completion: completion)
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

    // MARK: - 7. Scrolling Capture (VisionStitcher + PixelStrip Engine)
    public func captureScrollingArea(reverseDirection: Bool = false, maxSteps: Int = 18, completion: @escaping (NSImage?) -> Void) {
        // Ensure Accessibility and Automation permissions are present
        if !PermissionManager.shared.checkAccessibility() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Scrolling Capture needs Accessibility and Automation permissions so Screenshots can scroll through the window and capture full content.\n\nClick 'Grant Permission' to open System Settings."
            alert.addButton(withTitle: "Grant Permission")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.shared.requestAccessibility()
                PermissionManager.shared.requestAutomation()
            }
            completion(nil)
            return
        }

        captureInteractiveArea { firstImage in
            guard let first = firstImage, let rect = self.lastCapturedAreaRect else {
                completion(firstImage)
                return
            }

            var frames: [NSImage] = [first]
            let scrollCenter = CGPoint(x: rect.midX, y: rect.midY)
            let delta: Int32 = reverseDirection ? 6 : -6
            var consecutiveZeroShifts = 0

            // Step loop: warp cursor -> scroll -> wait -> capture -> measure shift -> terminate or continue
            func performStep(index: Int) {
                if index >= maxSteps || consecutiveZeroShifts >= 2 {
                    DispatchQueue.main.async {
                        let stitched = self.stitchVisionFrames(frames, reverse: reverseDirection)
                        completion(stitched ?? first)
                    }
                    return
                }

                // 1. Physically position the hardware cursor inside the capture area
                CGWarpMouseCursorPosition(scrollCenter)

                // 2. Post scroll wheel events (line + pixel)
                self.postScrollEvent(lines: delta, at: scrollCenter)

                // 3. Fallback: If previous shift was 0, trigger keyboard scroll via System Events
                if consecutiveZeroShifts > 0 {
                    self.postKeyboardScroll(reverse: reverseDirection)
                }

                // 4. Give the target window 350ms to finish scrolling and paint content
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.captureRegionDirect(rect: rect) { nextImg in
                        guard let nextImg = nextImg else {
                            performStep(index: index + 1)
                            return
                        }

                        // Measure shift between current last frame and newly captured frame
                        if let lastFrame = frames.last,
                           let shift = self.calculateShiftBetween(f1: lastFrame, f2: nextImg) {
                            if shift > 3 {
                                frames.append(nextImg)
                                consecutiveZeroShifts = 0
                            } else {
                                consecutiveZeroShifts += 1
                            }
                        } else {
                            consecutiveZeroShifts += 1
                        }

                        performStep(index: index + 1)
                    }
                }
            }

            performStep(index: 1)
        }
    }

    private func postScrollEvent(lines: Int32, at point: CGPoint? = nil) {
        let targetPoint = point ?? lastCapturedAreaRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero

        // Post line wheel event
        if let lineEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) {
            lineEvent.location = targetPoint
            lineEvent.post(tap: .cghidEventTap)
        }

        // Post continuous pixel wheel event for WebKit / Chrome / Electron smooth scrolling
        if let pixelEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: lines * 22, wheel2: 0, wheel3: 0) {
            pixelEvent.location = targetPoint
            pixelEvent.post(tap: .cghidEventTap)
        }
    }

    private func postKeyboardScroll(reverse: Bool) {
        // Key code 125 = Down Arrow, Key code 126 = Up Arrow
        let keyCode = reverse ? 126 : 125
        let script = NSAppleScript(source: "tell application \"System Events\" to key code \(keyCode)")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
    }

    // Measure vertical shift between two frames using Apple Vision + Pixel Strip matching fallback
    private func calculateShiftBetween(f1: NSImage, f2: NSImage) -> Int? {
        guard let t1 = f1.tiffRepresentation, let ci1 = CIImage(data: t1),
              let t2 = f2.tiffRepresentation, let ci2 = CIImage(data: t2) else { return nil }

        // Method 1: Apple Vision translational registration
        let req = VNTranslationalImageRegistrationRequest(targetedCIImage: ci2)
        let handler = VNImageRequestHandler(ciImage: ci1, options: [:])
        if (try? handler.perform([req])) != nil,
           let obs = req.results?.first as? VNImageTranslationAlignmentObservation {
            let shiftY = Int(round(abs(obs.alignmentTransform.ty)))
            let frameH = Int(ci1.extent.height)
            if shiftY > 5 && shiftY < Int(Double(frameH) * 0.95) {
                return shiftY
            }
        }

        // Method 2: Raw pixel strip template search fallback (Shottr overlayShiftStamp)
        guard let r1 = NSBitmapImageRep(data: t1), let r2 = NSBitmapImageRep(data: t2) else { return nil }
        return findPixelStripShift(prev: r1, next: r2)
    }

    // Fast pixel strip template matching
    private func findPixelStripShift(prev: NSBitmapImageRep, next: NSBitmapImageRep) -> Int? {
        let w = prev.pixelsWide
        let h = prev.pixelsHigh
        guard next.pixelsWide == w && next.pixelsHigh == h && h > 100 else { return nil }

        guard let p1 = prev.bitmapData, let p2 = next.bitmapData else { return nil }
        let rowBytes = prev.bytesPerRow

        let sampleH = 20
        let sampleStartPrev = max(10, h - 100)
        var bestShift: Int? = nil
        var minDiff = Int.max

        for candidateY in stride(from: 0, to: sampleStartPrev, by: 2) {
            var diff = 0
            let xStep = max(1, w / 16)
            for r in 0..<sampleH {
                let row1 = (sampleStartPrev + r) * rowBytes
                let row2 = (candidateY + r) * rowBytes
                for col in stride(from: 0, to: w, by: xStep) {
                    let off1 = row1 + col * 4
                    let off2 = row2 + col * 4
                    let dr = Int(p1[off1]) - Int(p2[off2])
                    let dg = Int(p1[off1 + 1]) - Int(p2[off2 + 1])
                    let db = Int(p1[off1 + 2]) - Int(p2[off2 + 2])
                    diff += abs(dr) + abs(dg) + abs(db)
                }
            }
            if diff < minDiff {
                minDiff = diff
                bestShift = sampleStartPrev - candidateY
            }
        }

        let totalSamples = sampleH * 16
        if let shift = bestShift, (minDiff / max(1, totalSamples)) < 28, shift > 4 {
            return shift
        }
        return nil
    }

    // Vision-based translational image alignment & raw stitch
    private func stitchVisionFrames(_ frames: [NSImage], reverse: Bool = false) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        guard frames.count > 1 else { return frames.first }

        var reps: [NSBitmapImageRep] = []
        for f in frames {
            guard let tiff = f.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            reps.append(rep)
        }

        let w = reps[0].pixelsWide
        let frameH = reps[0].pixelsHigh
        let rowBytes = w * 4

        var pairs: [(shift: Int, rep: NSBitmapImageRep)] = []

        for i in 1..<frames.count {
            if let shift = calculateShiftBetween(f1: frames[i - 1], f2: frames[i]),
               shift > 4 && shift < Int(Double(frameH) * 0.95) {
                pairs.append((shift: shift, rep: reps[i]))
            }
        }

        guard !pairs.isEmpty else { return frames.first }

        let totalH = frameH + pairs.reduce(0) { $0 + $1.shift }

        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: totalH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: rowBytes,
            bitsPerPixel: 32
        ), let dstPtr = outRep.bitmapData else { return nil }

        // Copy initial frame
        if let src0 = reps[0].bitmapData {
            memcpy(dstPtr, src0, frameH * rowBytes)
        }

        // Seamlessly stitch newly revealed rows
        var currentOffsetRows = frameH
        for pair in pairs {
            guard let nextSrc = pair.rep.bitmapData else { continue }
            let srcOffset = (frameH - pair.shift) * rowBytes
            let dstOffset = currentOffsetRows * rowBytes
            memcpy(dstPtr + dstOffset, nextSrc + srcOffset, pair.shift * rowBytes)
            currentOffsetRows += pair.shift
        }

        let result = NSImage(size: NSSize(
            width: frames[0].size.width,
            height: frames[0].size.height * CGFloat(totalH) / CGFloat(frameH)
        ))
        result.addRepresentation(outRep)
        return result
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
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [AnyObject],
              plist.count == 4 else {
            return nil
        }
        let nums = plist.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard nums.count == 4 else { return nil }
        return CGRect(x: CGFloat(nums[0]), y: CGFloat(nums[1]), width: CGFloat(nums[2]), height: CGFloat(nums[3]))
    }
}
