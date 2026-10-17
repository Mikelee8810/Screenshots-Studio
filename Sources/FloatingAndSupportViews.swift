import SwiftUI
import AppKit

// MARK: - 1. Pin Window Controller (Floating Borderless Reference Card with X-Ray & Custom HUD)

class PinViewState: ObservableObject {
    @Published var isSemiTransparent: Bool = false
    @Published var isHovering: Bool = false
}

public class PinWindowManager {
    public static let shared = PinWindowManager()
    private var pinnedWindows: [NSWindow] = []

    public func pinImage(_ image: NSImage, onEdit: @escaping (NSImage) -> Void) {
        let size = NSSize(width: max(220, min(800, image.size.width * 0.5)), height: max(160, min(600, image.size.height * 0.5)))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false

        let view = PinnedImageView(image: image, window: window, onEdit: {
            window.close()
            onEdit(image)
        }, onClose: {
            window.close()
            self.pinnedWindows.removeAll { $0 == window }
        })

        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        pinnedWindows.append(window)
    }
}

struct PinnedImageView: View {
    let image: NSImage
    weak var window: NSWindow?
    let onEdit: () -> Void
    let onClose: () -> Void

    @StateObject private var state = PinViewState()
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .opacity(state.isSemiTransparent ? 0.42 : 1.0)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StudioTheme.borderStrong, lineWidth: 1)
                )

            if state.isHovering {
                HStack(spacing: 6) {
                    Button(action: { state.isSemiTransparent.toggle() }) {
                        Image(systemName: state.isSemiTransparent ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(StudioTheme.textPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(StudioTheme.bgBar.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle X-Ray Semi-Transparency")

                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.writeObjects([image])
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(StudioTheme.textPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(StudioTheme.bgBar.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Image")

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(StudioTheme.textPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(StudioTheme.bgBar.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .help("Re-open in Screenshots Studio")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(StudioTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .help("Close Pinned Window")
                }
                .padding(8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.state.isHovering = hovering
            }
        }
        .contextMenu {
            Button("Edit in Studio") { onEdit() }
            Button("Copy to Clipboard") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
            }
            Divider()
            Button("50% Scale") { resizeWindow(scale: 0.25) }
            Button("100% Scale") { resizeWindow(scale: 0.5) }
            Button("200% Scale") { resizeWindow(scale: 1.0) }
            Divider()
            Button(state.isSemiTransparent ? "Opaque (100%)" : "X-Ray Semi-transparent") {
                state.isSemiTransparent.toggle()
            }
            Divider()
            Button("Close Pin") { onClose() }
        }
    }

    private func resizeWindow(scale: CGFloat) {
        guard let win = window else { return }
        let newSize = NSSize(width: max(140, image.size.width * scale), height: max(100, image.size.height * scale))
        var frame = win.frame
        frame.size = newSize
        win.setFrame(frame, display: true, animate: true)
    }
}

// MARK: - 2. Floating Thumbnail Preview Window

public class ThumbnailPreviewManager {
    public static let shared = ThumbnailPreviewManager()
    private var previewWindow: NSWindow?

    public func showThumbnail(
        for image: NSImage,
        onEdit: @escaping (NSImage) -> Void,
        onPin: @escaping (NSImage) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onSave: @escaping (NSImage) -> Void
    ) {
        previewWindow?.close()

        let width: CGFloat = 300
        let height: CGFloat = 204
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.maxX - width - 24, y: screenFrame.minY + 24)

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        let view = ThumbnailPreviewCard(
            image: image,
            onEdit: {
                window.close()
                onEdit(image)
            },
            onCopy: {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
                window.close()
            },
            onSave: {
                onSave(image)
                window.close()
            },
            onPin: {
                window.close()
                onPin(image)
            },
            onOCR: {
                window.close()
                onOCR(image)
            },
            onDismiss: {
                window.close()
            }
        )

        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        self.previewWindow = window
    }
}

struct ThumbnailPreviewCard: View {
    let image: NSImage
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onDismiss: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 280, height: 140)
                    .clipped()
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(StudioTheme.borderStrong, lineWidth: 1))
                    .onTapGesture { onEdit() }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(6)
            }

            HStack(spacing: 6) {
                StudioActionPill(title: "Edit", systemIcon: "pencil", isPrimary: true, action: onEdit)
                StudioActionPill(title: "Copy", systemIcon: "doc.on.doc", action: onCopy)
                StudioActionPill(title: "", systemIcon: "arrow.down.to.line", action: onSave)
                StudioActionPill(title: "", systemIcon: "pin.fill", action: onPin)
                StudioActionPill(title: "", systemIcon: "text.viewfinder", action: onOCR)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(StudioTheme.bgBar)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(StudioTheme.borderStrong, lineWidth: 1))
        )
        .preferredColorScheme(theme.colorScheme)
    }
}

// MARK: - 3. Screenshot Library & OCR Search Indexer

class LibraryBrowserState: ObservableObject {
    @Published var items: [LibraryScreenshotItem] = []
    @Published var searchQuery: String = ""
    @Published var layoutMode: Int = 1
}

public struct LibraryBrowserView: View {
    public var onSelectImage: (NSImage) -> Void
    @StateObject private var state = LibraryBrowserState()
    @ObservedObject private var theme = ThemeManager.shared

    public init(onSelectImage: @escaping (NSImage) -> Void) {
        self.onSelectImage = onSelectImage
    }

    var filteredItems: [LibraryScreenshotItem] {
        if state.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return state.items
        }
        return state.items.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(state.searchQuery) ||
            $0.ocrIndexedText.localizedCaseInsensitiveContains(state.searchQuery)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(StudioTheme.textSecondary)
                    TextField("Search saved screenshots by filename or OCR text...", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .foregroundColor(StudioTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(StudioTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.border, lineWidth: 1))

                HStack(spacing: 4) {
                    ForEach([(0, "square.grid.4x3.fill"), (1, "square.grid.2x2.fill"), (2, "rectangle.grid.1x2.fill")], id: \.0) { mode, icon in
                        StudioActionPill(title: "", systemIcon: icon, isPrimary: state.layoutMode == mode) {
                            state.layoutMode = mode
                        }
                    }
                }

                StudioActionPill(title: "Choose Folder", systemIcon: "folder") {
                    pickFolder()
                }

                StudioActionPill(title: "", systemIcon: "arrow.clockwise") {
                    scanFolder()
                }
            }
            .padding(14)
            .background(StudioTheme.bgBar)

            Rectangle().fill(StudioTheme.border).frame(height: 1)

            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42))
                        .foregroundColor(StudioTheme.textMuted)
                    Text("No Saved Screenshots Found")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(StudioTheme.textPrimary)
                    Text("Folder: \(ScreenCaptureManager.shared.defaultSaveFolder.path)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(StudioTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudioTheme.bgCanvas)
            } else {
                ScrollView {
                    let colWidth: CGFloat = state.layoutMode == 0 ? 160 : (state.layoutMode == 1 ? 230 : 340)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: colWidth), spacing: 14)], spacing: 14) {
                        ForEach(filteredItems) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                if let nsImg = NSImage(contentsOf: item.url) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: colWidth * 0.62)
                                        .clipped()
                                        .cornerRadius(8)
                                        .onTapGesture(count: 2) {
                                            onSelectImage(nsImg)
                                        }
                                        .contextMenu {
                                            Button("Open in Studio Editor") { onSelectImage(nsImg) }
                                            Button("Pin Floating Window") {
                                                PinWindowManager.shared.pinImage(nsImg, onEdit: onSelectImage)
                                            }
                                            Button("Reveal in Finder") {
                                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                            }
                                        }
                                }
                                HStack {
                                    Text(item.url.lastPathComponent)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(StudioTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(item.dimensions.width))×\(Int(item.dimensions.height))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(StudioTheme.textSecondary)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 11).fill(StudioTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(StudioTheme.border, lineWidth: 1))
                        }
                    }
                    .padding(18)
                }
                .background(StudioTheme.bgCanvas)
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .frame(minWidth: 780, minHeight: 520)
        .onAppear(perform: scanFolder)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            ScreenCaptureManager.shared.defaultSaveFolder = url
            scanFolder()
        }
    }

    private func scanFolder() {
        let folder = ScreenCaptureManager.shared.defaultSaveFolder
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let imageExts = ["png", "jpg", "jpeg", "gif", "tiff", "webp"]
        var loaded: [LibraryScreenshotItem] = []

        for url in urls where imageExts.contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let date = values?.creationDate ?? Date.distantPast
            let fileSize = Int64(values?.fileSize ?? 0)
            let size = NSImage(contentsOf: url)?.size ?? .zero
            loaded.append(LibraryScreenshotItem(url: url, date: date, dimensions: size, fileSize: fileSize, ocrIndexedText: ""))
        }

        loaded.sort { $0.date > $1.date }
        self.state.items = Array(loaded.prefix(60))
    }
}

// MARK: - 4. Studio Preferences Window (Appearance, Window Level, Shortcuts, S3, Snake Easter Egg)

class PreferencesState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var afterGrabCopy: Bool = UserDefaults.standard.object(forKey: "afterGrabCopy") as? Bool ?? true {
        didSet { UserDefaults.standard.set(afterGrabCopy, forKey: "afterGrabCopy") }
    }
    @Published var afterGrabSave: Bool = UserDefaults.standard.bool(forKey: "afterGrabSave") {
        didSet { UserDefaults.standard.set(afterGrabSave, forKey: "afterGrabSave") }
    }
    @Published var afterGrabShow: Bool = UserDefaults.standard.object(forKey: "afterGrabShow") as? Bool ?? true {
        didSet { UserDefaults.standard.set(afterGrabShow, forKey: "afterGrabShow") }
    }
    @Published var saveOnEsc: Bool = UserDefaults.standard.bool(forKey: "saveOnEsc") {
        didSet { UserDefaults.standard.set(saveOnEsc, forKey: "saveOnEsc") }
    }
    @Published var copyOnEsc: Bool = UserDefaults.standard.object(forKey: "copyOnEsc") as? Bool ?? true {
        didSet { UserDefaults.standard.set(copyOnEsc, forKey: "copyOnEsc") }
    }
    // Defaults to FALSE so the main window can be placed behind other windows normally
    @Published var editorAlwaysOnTop: Bool = UserDefaults.standard.bool(forKey: "editorAlwaysOnTop") {
        didSet {
            UserDefaults.standard.set(editorAlwaysOnTop, forKey: "editorAlwaysOnTop")
            NotificationCenter.default.post(name: Notification.Name("ScreenshotsUpdateWindowLevel"), object: nil)
        }
    }
    @Published var ocrRemoveBreaks: Bool = UserDefaults.standard.bool(forKey: "ocrRemoveBreaks") {
        didSet { UserDefaults.standard.set(ocrRemoveBreaks, forKey: "ocrRemoveBreaks") }
    }
    @Published var realPixels: Bool = UserDefaults.standard.bool(forKey: "realPixels") {
        didSet { UserDefaults.standard.set(realPixels, forKey: "realPixels") }
    }
    @Published var windowShadow: Bool = UserDefaults.standard.bool(forKey: "windowShadow") {
        didSet { UserDefaults.standard.set(windowShadow, forKey: "windowShadow") }
    }
    @Published var saveFormat: String = UserDefaults.standard.string(forKey: "saveFormat") ?? "PNG" {
        didSet { UserDefaults.standard.set(saveFormat, forKey: "saveFormat") }
    }
    @Published var colorFormat: String = UserDefaults.standard.string(forKey: "colorFormat") ?? ColorCodeFormat.hex.rawValue {
        didSet { UserDefaults.standard.set(colorFormat, forKey: "colorFormat") }
    }
    @Published var s3Endpoint: String = UserDefaults.standard.string(forKey: "s3Endpoint") ?? "" {
        didSet { UserDefaults.standard.set(s3Endpoint, forKey: "s3Endpoint") }
    }
    @Published var s3Bucket: String = UserDefaults.standard.string(forKey: "s3Bucket") ?? "" {
        didSet { UserDefaults.standard.set(s3Bucket, forKey: "s3Bucket") }
    }
    @Published var s3PublicUrl: String = UserDefaults.standard.string(forKey: "s3PublicUrl") ?? "" {
        didSet { UserDefaults.standard.set(s3PublicUrl, forKey: "s3PublicUrl") }
    }
    @Published var showSnakeEasterEgg: Bool = false
}

public struct PreferencesView: View {
    @StateObject private var state = PreferencesState()
    @ObservedObject private var theme = ThemeManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([
                    (0, "General & Theme", "slider.horizontal.3"),
                    (1, "Shortcuts", "command"),
                    (2, "Cloud & S3", "icloud.and.arrow.up"),
                    (3, "Advanced", "cpu")
                ], id: \.0) { idx, title, icon in
                    StudioActionPill(title: title, systemIcon: icon, isPrimary: state.selectedTab == idx) {
                        state.selectedTab = idx
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(StudioTheme.bgBar)

            Rectangle().fill(StudioTheme.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state.selectedTab == 0 {
                        prefsCard(title: "APPEARANCE & THEME") {
                            HStack {
                                Text("Studio Color Theme:")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(StudioTheme.textPrimary)
                                Spacer()
                                StudioSegmentedPills(items: AppearanceMode.allCases, selection: $theme.mode)
                            }
                        }

                        prefsCard(title: "WINDOW BEHAVIOR") {
                            Toggle("Keep Studio Editor floating above all windows (Disable to allow placing behind other apps)", isOn: $state.editorAlwaysOnTop)
                            Toggle("Copy image to clipboard when closing on Esc", isOn: $state.copyOnEsc)
                            Toggle("Save image to disk when closing on Esc", isOn: $state.saveOnEsc)
                        }

                        prefsCard(title: "POST-CAPTURE WORKFLOW") {
                            Toggle("Open Studio Editor / Preview after capture", isOn: $state.afterGrabShow)
                            Toggle("Automatically copy screenshot to clipboard", isOn: $state.afterGrabCopy)
                            Toggle("Automatically save file to default folder", isOn: $state.afterGrabSave)
                        }
                    } else if state.selectedTab == 1 {
                        prefsCard(title: "GLOBAL CAPTURE SHORTCUTS") {
                            shortcutRow("Fullscreen Screenshot", "⌘ ⇧ 1")
                            shortcutRow("Area Screenshot", "⌘ ⇧ 2")
                            shortcutRow("Scrolling Capture (Down)", "⌘ ⇧ 3")
                            shortcutRow("Reverse Scrolling Capture (Up)", "⌘ ⇧ 4")
                            shortcutRow("Capture Any Window", "⌘ ⇧ W")
                            shortcutRow("Capture Active Window", "⌘ ⇧ A")
                            shortcutRow("Repeat Last Area Capture", "⌘ ⇧ R")
                            shortcutRow("Recognize Text / QR (OCR)", "⌘ ⇧ O")
                        }
                        prefsCard(title: "SINGLE-KEY STUDIO CANVAS SHORTCUTS") {
                            Text("[V] Select/Move  •  [C] Crop  •  [A] Arrow  •  [R] Rectangle  •  [O] Oval  •  [L] Line  •  [F] Freehand  •  [H] Highlighter  •  [T] Text  •  [N] Step Counter  •  [S] Spotlight  •  [M] Magnifier  •  [B] Pixelate/Blur/Erase  •  [U] Ruler  •  [P] Pixels/Points  •  [Tab] Copy Pixel Color")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(StudioTheme.textSecondary)
                        }
                    } else if state.selectedTab == 2 {
                        prefsCard(title: "S3 / CLOUDFLARE R2 DIRECT UPLOAD") {
                            TextField("S3 Endpoint URL (e.g. https://<id>.r2.cloudflarestorage.com)", text: $state.s3Endpoint)
                                .textFieldStyle(.roundedBorder)
                            TextField("Bucket Name", text: $state.s3Bucket)
                                .textFieldStyle(.roundedBorder)
                            TextField("Public Domain URL", text: $state.s3PublicUrl)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        prefsCard(title: "OCR, RETINA & COLOR SETTINGS") {
                            Toggle("Strip line breaks when copying OCR text", isOn: $state.ocrRemoveBreaks)
                            Toggle("Include macOS drop shadow in Window Captures", isOn: $state.windowShadow)
                            Picker("Eyedropper Color Format:", selection: $state.colorFormat) {
                                ForEach(ColorCodeFormat.allCases) { fmt in
                                    Text(fmt.rawValue).tag(fmt.rawValue)
                                }
                            }
                        }

                        prefsCard(title: "ABOUT SCREENSHOTS STUDIO PRO") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Screenshots Studio Pro v2.2 — Native macOS Design")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(StudioTheme.textPrimary)
                                    Text("All Pro Features Unlocked • Light & Dark Mode • Zero Nag Popups")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(red: 0.2, green: 0.78, blue: 0.42))
                                }
                                Spacer()
                                StudioActionPill(
                                    title: state.showSnakeEasterEgg ? "Hide Snake" : "Play Snake 🐍",
                                    systemIcon: "gamecontroller.fill"
                                ) {
                                    state.showSnakeEasterEgg.toggle()
                                }
                            }
                            if state.showSnakeEasterEgg {
                                MiniSnakeGameView()
                                    .frame(height: 150)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(StudioTheme.bgCanvas)
        }
        .preferredColorScheme(theme.colorScheme)
        .frame(width: 580, height: 470)
    }

    @ViewBuilder
    private func prefsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(StudioTheme.textMuted)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(StudioTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(StudioTheme.border, lineWidth: 1))
        }
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundColor(StudioTheme.textPrimary)
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundColor(StudioTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(StudioTheme.bgCanvas))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(StudioTheme.border, lineWidth: 1))
        }
    }
}

class SnakeGameState: ObservableObject {
    @Published var snake: [CGPoint] = [CGPoint(x: 5, y: 4), CGPoint(x: 4, y: 4), CGPoint(x: 3, y: 4)]
    @Published var food: CGPoint = CGPoint(x: 10, y: 5)
    @Published var dir: CGPoint = CGPoint(x: 1, y: 0)
    @Published var score: Int = 0
}

struct MiniSnakeGameView: View {
    @StateObject private var game = SnakeGameState()
    let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            StudioTheme.bgCanvas
            GeometryReader { _ in
                let cellSize: CGFloat = 14
                ForEach(0..<game.snake.count, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(idx == 0 ? Color.green : Color.green.opacity(0.75))
                        .frame(width: cellSize - 2, height: cellSize - 2)
                        .position(x: game.snake[idx].x * cellSize + cellSize / 2, y: game.snake[idx].y * cellSize + cellSize / 2)
                }
                Circle()
                    .fill(StudioTheme.accent)
                    .frame(width: cellSize - 2, height: cellSize - 2)
                    .position(x: game.food.x * cellSize + cellSize / 2, y: game.food.y * cellSize + cellSize / 2)
            }
            VStack {
                HStack {
                    Text("SNAKE SCORE: \(game.score)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Spacer()
                    HStack(spacing: 4) {
                        StudioActionPill(title: "←", systemIcon: "") { if game.dir.x == 0 { game.dir = CGPoint(x: -1, y: 0) } }
                        StudioActionPill(title: "↑", systemIcon: "") { if game.dir.y == 0 { game.dir = CGPoint(x: 0, y: -1) } }
                        StudioActionPill(title: "↓", systemIcon: "") { if game.dir.y == 0 { game.dir = CGPoint(x: 0, y: 1) } }
                        StudioActionPill(title: "→", systemIcon: "") { if game.dir.x == 0 { game.dir = CGPoint(x: 1, y: 0) } }
                    }
                }
                .padding(6)
                Spacer()
            }
        }
        .onReceive(timer) { _ in
            guard let head = game.snake.first else { return }
            let next = CGPoint(
                x: (head.x + game.dir.x + 30).truncatingRemainder(dividingBy: 30),
                y: (head.y + game.dir.y + 10).truncatingRemainder(dividingBy: 10)
            )
            game.snake.insert(next, at: 0)
            if Int(next.x) == Int(game.food.x) && Int(next.y) == Int(game.food.y) {
                game.score += 10
                game.food = CGPoint(x: CGFloat(Int.random(in: 1..<28)), y: CGFloat(Int.random(in: 2..<9)))
            } else {
                game.snake.removeLast()
            }
        }
    }
}
