import AppKit
import AVFoundation
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Screen Recorder (ScreenCaptureKit -> H.264 MP4, plus GIF export)

// MARK: - Screen Recorder (ScreenCaptureKit -> H.264 MP4, plus GIF export)

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    static let shared = ScreenRecorder()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private let queue = DispatchQueue(label: "com.screenshots.recorder")

    private(set) var isRecording = false
    private(set) var lastRecordingURL: URL?

    // MARK: Start

    func start(completion: @escaping (Error?) -> Void) {
        guard !isRecording else { completion(nil); return }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    throw NSError(domain: "Screenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found to record."])
                }

                let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
                let width = (display.width * scale) & ~1
                let height = (display.height * scale) & ~1

                let config = SCStreamConfiguration()
                config.width = width
                config.height = height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true
                config.queueDepth = 6

                let folder = ScreenCaptureManager.shared.defaultSaveFolder
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let url = folder.appendingPathComponent("REC-\(formatter.string(from: Date())).mp4")
                try? FileManager.default.removeItem(at: url)

                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else {
                    throw NSError(domain: "Screenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not configure the video writer."])
                }
                writer.add(input)

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

                self.writer = writer
                self.input = input
                self.sessionStarted = false
                self.lastRecordingURL = url
                self.stream = stream

                try await stream.startCapture()
                self.isRecording = true
                completion(nil)
            } catch {
                self.cleanup()
                completion(error)
            }
        }
    }

    // MARK: Stop

    func stop(completion: @escaping (URL?) -> Void) {
        guard isRecording, let stream = stream else { completion(nil); return }
        isRecording = false
        Task {
            try? await stream.stopCapture()
            queue.async {
                guard let writer = self.writer, let input = self.input else {
                    completion(nil)
                    return
                }
                guard self.sessionStarted else {
                    writer.cancelWriting()
                    self.cleanup()
                    completion(nil)
                    return
                }
                input.markAsFinished()
                writer.finishWriting {
                    let url = writer.status == .completed ? self.lastRecordingURL : nil
                    self.cleanup()
                    completion(url)
                }
            }
        }
    }

    private func cleanup() {
        stream = nil
        writer = nil
        input = nil
        sessionStarted = false
        isRecording = false
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let writer = writer, let input = input else { return }

        // Only write fully rendered frames (skip idle / blank status frames).
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue else { return }

        if !sessionStarted {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        if writer.status == .writing, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Recording stream stopped: \(error.localizedDescription)")
    }

    // MARK: GIF export

    /// Converts a recording to a looping GIF (10 fps, max 800px wide, first 20 seconds).
    func exportGIF(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: videoURL)
            let seconds = min(CMTimeGetSeconds(asset.duration), 20)
            guard seconds.isFinite, seconds > 0 else { completion(nil); return }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 800, height: 800)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            let fps = 10.0
            let frameCount = max(1, Int(seconds * fps))
            let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")

            guard let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                completion(nil)
                return
            }
            CGImageDestinationSetProperties(dest, [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
            ] as CFDictionary)

            let frameProps = [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / fps]
            ] as CFDictionary

            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
                if let frame = try? generator.copyCGImage(at: time, actualTime: nil) {
                    CGImageDestinationAddImage(dest, frame, frameProps)
                }
            }
            completion(CGImageDestinationFinalize(dest) ? gifURL : nil)
        }
    }
}
