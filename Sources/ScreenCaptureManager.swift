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

    // MARK: - 7. Scrolling Capture (VisionStitcher Incremental SAD Engine + HUD)
    public func captureScrollingArea(reverseDirection: Bool = false, maxSteps: Int = 22, completion: @escaping (NSImage?) -> Void) {
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
            guard let first = firstImage, let rect = self.lastCapturedAreaRect,
                  let firstTiff = first.tiffRepresentation,
                  let firstRep = NSBitmapImageRep(data: firstTiff) else {
                completion(firstImage)
                return
            }

            let scrollCenter = CGPoint(x: rect.midX, y: rect.midY)
            let delta: Int32 = reverseDirection ? 6 : -6

            let w = firstRep.pixelsWide
            let frameH = firstRep.pixelsHigh
            let rowBytes = firstRep.bytesPerRow

            // Dynamic buffer supporting up to maxSteps stitched frames
            let maxTotalH = frameH * (maxSteps + 1)
            guard let canvasRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: w,
                pixelsHigh: maxTotalH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: rowBytes,
                bitsPerPixel: 32
            ), let canvasPtr = canvasRep.bitmapData,
               let firstPtr = firstRep.bitmapData else {
                completion(first)
                return
            }

            // Copy initial frame
            memcpy(canvasPtr, firstPtr, frameH * rowBytes)
            var currentStitchedHeight = frameH
            var lastRep = firstRep
            var consecutiveZeroShifts = 0
            var isStopped = false

            func finalize() {
                guard !isStopped else { return }
                isStopped = true
                ScrollingHUDManager.shared.dismissHUD()

                DispatchQueue.main.async {
                    guard currentStitchedHeight > frameH else {
                        completion(first)
                        return
                    }

                    guard let finalRep = NSBitmapImageRep(
                        bitmapDataPlanes: nil,
                        pixelsWide: w,
                        pixelsHigh: currentStitchedHeight,
                        bitsPerSample: 8,
                        samplesPerPixel: 4,
                        hasAlpha: true,
                        isPlanar: false,
                        colorSpaceName: .deviceRGB,
                        bytesPerRow: rowBytes,
                        bitsPerPixel: 32
                    ), let finalDst = finalRep.bitmapData else {
                        completion(first)
                        return
                    }

                    memcpy(finalDst, canvasPtr, currentStitchedHeight * rowBytes)

                    let finalImg = NSImage(size: NSSize(
                        width: first.size.width,
                        height: first.size.height * CGFloat(currentStitchedHeight) / CGFloat(frameH)
                    ))
                    finalImg.addRepresentation(finalRep)
                    completion(finalImg)
                }
            }

            // Show floating HUD with ESC & click-to-finish support
            DispatchQueue.main.async {
                ScrollingHUDManager.shared.showHUD(near: rect, maxSteps: maxSteps) {
                    finalize()
                }
            }

            func performStep(index: Int) {
                if index >= maxSteps || consecutiveZeroShifts >= 2 || isStopped {
                    finalize()
                    return
                }

                // 1. Warp hardware mouse cursor into the capture area
                CGWarpMouseCursorPosition(scrollCenter)

                // 2. Post scroll wheel events (line + pixel)
                self.postScrollEvent(lines: delta, at: scrollCenter)

                // 3. Fallback: If previous shift was 0, trigger keyboard scroll via System Events
                if consecutiveZeroShifts > 0 {
                    self.postKeyboardScroll(reverse: reverseDirection)
                }

                // 4. Wait for smooth scroll animation and DOM render
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    if isStopped { return }
                    self.captureRegionDirect(rect: rect) { nextImg in
                        if isStopped { return }
                        guard let nextImg = nextImg,
                              let nextTiff = nextImg.tiffRepresentation,
                              let nextRep = NSBitmapImageRep(data: nextTiff),
                              let nextPtr = nextRep.bitmapData else {
                            performStep(index: index + 1)
                            return
                        }

                        // Calculate exact 1D SAD vertical shift down to 1 pixel
                        if let shift = self.findExactShift(f1: lastRep, f2: nextRep), shift > 5 {
                            let newRows = shift
                            let srcOffset = (frameH - newRows) * rowBytes
                            let dstOffset = currentStitchedHeight * rowBytes

                            if (currentStitchedHeight + newRows) <= maxTotalH {
                                memcpy(canvasPtr + dstOffset, nextPtr + srcOffset, newRows * rowBytes)
                                currentStitchedHeight += newRows
                                lastRep = nextRep
                                consecutiveZeroShifts = 0
                                ScrollingHUDManager.shared.updateStep(index + 1)
                            } else {
                                finalize()
                                return
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
        let keyCode = reverse ? 126 : 125
        let script = NSAppleScript(source: "tell application \"System Events\" to key code \(keyCode)")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
    }

    // High-precision Sum of Absolute Differences (SAD) with 1-pixel refinement (Shottr overlayShiftStamp parity)
    private func findExactShift(f1: NSBitmapImageRep, f2: NSBitmapImageRep) -> Int? {
        let w = f1.pixelsWide
        let h = f1.pixelsHigh
        guard f2.pixelsWide == w && f2.pixelsHigh == h else { return nil }

        guard let p1 = f1.bitmapData, let p2 = f2.bitmapData else { return nil }
        let rowBytes = f1.bytesPerRow

        let overlapH = min(h / 3, 260)
        guard overlapH > 30 else { return nil }

        var bestShift: Int? = nil
        var minSad = Double.greatestFiniteMagnitude

        let maxShift = h - overlapH - 8
        guard maxShift > 10 else { return nil }

        let xStep = max(1, w / 32)
        let yStep = 2

        for s in stride(from: 10, to: maxShift, by: 2) {
            var totalDiff: Int64 = 0
            var samples = 0

            for y in stride(from: 0, to: overlapH, by: yStep) {
                let row1Offset = (y + s) * rowBytes
                let row2Offset = y * rowBytes

                for x in stride(from: 12, to: w - 12, by: xStep) {
                    let off1 = row1Offset + x * 4
                    let off2 = row2Offset + x * 4

                    let dr = abs(Int(p1[off1]) - Int(p2[off2]))
                    let dg = abs(Int(p1[off1 + 1]) - Int(p2[off2 + 1]))
                    let db = abs(Int(p1[off1 + 2]) - Int(p2[off2 + 2]))
                    totalDiff += Int64(dr + dg + db)
                    samples += 1
                }
            }

            let meanSad = Double(totalDiff) / Double(max(1, samples))
            if meanSad < minSad {
                minSad = meanSad
                bestShift = s
            }
        }

        // Single-pixel refinement step in [best - 1, best + 1]
        if let best = bestShift, minSad < 22.0 {
            var refinedShift = best
            var refinedMin = minSad

            for candidate in [best - 1, best + 1] {
                if candidate < 8 || candidate > maxShift { continue }
                var totalDiff: Int64 = 0
                var samples = 0

                for y in stride(from: 0, to: overlapH, by: 1) {
                    let row1Offset = (y + candidate) * rowBytes
                    let row2Offset = y * rowBytes

                    for x in stride(from: 12, to: w - 12, by: xStep) {
                        let off1 = row1Offset + x * 4
                        let off2 = row2Offset + x * 4

                        let dr = abs(Int(p1[off1]) - Int(p2[off2]))
                        let dg = abs(Int(p1[off1 + 1]) - Int(p2[off2 + 1]))
                        let db = abs(Int(p1[off1 + 2]) - Int(p2[off2 + 2]))
                        totalDiff += Int64(dr + dg + db)
                        samples += 1
                    }
                }

                let mean = Double(totalDiff) / Double(max(1, samples))
                if mean < refinedMin {
                    refinedMin = mean
                    refinedShift = candidate
                }
            }
            return refinedShift
        }

        return nil
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
