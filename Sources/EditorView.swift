import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Studio Editor State

class EditorState: ObservableObject {
    @Published var currentTool: ToolMode = .arrow
    @Published var strokeColor: Color = StudioTheme.accent
    @Published var strokeWidth: CGFloat = 3.5
    @Published var annotations: [AnnotationItem] = []
    @Published var undoStack: [[AnnotationItem]] = []
    @Published var redoStack: [[AnnotationItem]] = []
    @Published var activeItem: AnnotationItem? = nil
    @Published var selectedItemID: UUID? = nil
    @Published var dragStartSnapshot: AnnotationItem? = nil
    @Published var counterStep: Int = 1

    // Sub-style options
    @Published var arrowStyle: ArrowStyle = .single
    @Published var fillStyle: ShapeFillStyle = .transparent
    @Published var concealMode: ConcealMode = .pixelate
    @Published var fontStyle: TextFontStyle = .sans
    @Published var isDashed: Bool = false

    // Zoom & Pixels/Points
    @Published var zoomScale: CGFloat = 1.0
    @Published var showLogicalPoints: Bool = false

    // Live Eyedropper, Loupe & Color Format
    @Published var hoverLocation: CGPoint = .zero
    @Published var isHoveringCanvas: Bool = false
    @Published var hoveredColor: NSColor = NSColor(srgbRed: 1.0, green: 0.24, blue: 0.19, alpha: 1.0)
    @Published var colorFormat: ColorCodeFormat = .hex
    @Published var showLoupe: Bool = false

    // Window Float Toggle (Defaults to FALSE so window behaves like a normal macOS app)
    @Published var isFloatingWindow: Bool = UserDefaults.standard.bool(forKey: "editorAlwaysOnTop") {
        didSet {
            UserDefaults.standard.set(isFloatingWindow, forKey: "editorAlwaysOnTop")
            NotificationCenter.default.post(name: Notification.Name("ScreenshotsUpdateWindowLevel"), object: nil)
        }
    }

    // Backdrop Studio
    @Published var showBackdropInspector: Bool = false
    @Published var backdrop: BackdropConfig = BackdropConfig()

    // Image Resize Sheet
    @Published var showResizePopover: Bool = false
    @Published var targetWidthText: String = "1200"
    @Published var targetHeightText: String = "800"

    // Inline Text Entry on Canvas
    @Published var pendingTextPoint: CGPoint? = nil
    @Published var textDraft: String = ""

    // Status Toast Banner
    @Published var toastMessage: String? = nil

    // OCR Sheet
    @Published var ocrResultText: String = ""
    @Published var showingOcrAlert: Bool = false

    func pushUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
        if undoStack.count > 40 {
            undoStack.removeFirst()
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedItemID = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func deleteSelected() {
        guard let id = selectedItemID else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedItemID = nil
        showToast("Deleted selected annotation")
    }

    func showToast(_ text: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if self.toastMessage == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Main Studio Editor View

public struct EditorView: View {
    @Binding public var image: NSImage?
    @StateObject private var state = EditorState()
    @ObservedObject private var theme = ThemeManager.shared

    public init(image: Binding<NSImage?>) {
        self._image = image
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Clean Top Header Bar (with 78px Traffic-Light Safe Area)
            topStudioHeaderBar

            Rectangle()
                .fill(StudioTheme.border)
                .frame(height: 1)

            // MARK: - 2. Main Interactive Workspace + Floating Bottom Glass Dock + Optional Backdrop Drawer
            HStack(spacing: 0) {
                ZStack {
                    // Adaptive dot-grid studio background
                    StudioCanvasGridBackground()

                    if let img = image {
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            renderedCanvasView(for: img)
                                .scaleEffect(state.zoomScale)
                                .padding(.top, 36)
                                .padding(.horizontal, 48)
                                .padding(.bottom, 128) // Extra space for floating bottom dock
                        }
                    } else {
                        emptyWorkspaceWelcomeView
                    }

                    // Inline Canvas Text Input Box when placing ObjText
                    if let pt = state.pendingTextPoint {
                        floatingTextEntryHUD(at: pt)
                    }

                    // Floating Bottom Glass Instrument Dock + Contextual Style Pill + Zoom Pill
                    VStack(spacing: 8) {
                        Spacer()

                        // Contextual Style Bar (Color Swatches + Stroke Weight + Tool Sub-Modes + Undo/Redo)
                        floatingContextualStylePill

                        // Bottom Dock Row: 15 Custom Vector Tools + Zoom Pill
                        HStack(spacing: 12) {
                            floatingBottomToolDock

                            if image != nil {
                                zoomControlPill
                            }
                        }
                    }
                    .padding(.bottom, 16)

                    // Toast Notification Pill
                    if let toast = state.toastMessage {
                        VStack {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(red: 0.2, green: 0.88, blue: 0.48))
                                Text(toast)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.84))
                                    .overlay(Capsule().stroke(StudioTheme.borderStrong, lineWidth: 1))
                            )
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                            .padding(.top, 14)
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                if state.showBackdropInspector {
                    Rectangle()
                        .fill(StudioTheme.border)
                        .frame(width: 1)

                    BackdropStudioSidebar(config: $state.backdrop) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            state.showBackdropInspector = false
                        }
                    }
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .background(StudioTheme.bgCanvas)
        .preferredColorScheme(theme.colorScheme)
        .frame(minWidth: 1080, minHeight: 700)
        .background(
            KeyboardEventMonitorView { event in
                handleKeyDown(event)
            }
        )
        .alert("Recognized Text & QR Codes", isPresented: $state.showingOcrAlert) {
            Button("Copy to Clipboard") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(state.ocrResultText, forType: .string)
                state.showToast("Copied recognized text to clipboard")
            }
            Button("Close", role: .cancel) {}
        } message: {
            Text(state.ocrResultText.isEmpty ? "No readable text or QR code found in image." : state.ocrResultText)
        }
    }

    // MARK: - Top Studio Header Bar (78px Leading Safe Area for macOS Traffic Lights)
    private var topStudioHeaderBar: some View {
        HStack(spacing: 8) {
            // Left: New Capture Menu + Dimensions Badge + Live Eyedropper + Loupe Toggle
            HStack(spacing: 6) {
                Menu {
                    Button("Area Capture (⌃⇧2)") {
                        NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerArea"), object: nil)
                    }
                    Button("Window Capture (⌃⇧W)") {
                        NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerWindow"), object: nil)
                    }
                    Button("Fullscreen Capture (⌃⇧1)") {
                        NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerFullscreen"), object: nil)
                    }
                    Button("Scrolling Capture (⌃⇧3)") {
                        NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerScrolling"), object: nil)
                    }
                    Divider()
                    Button("Paste Image from Clipboard (⌘V)") {
                        loadFromClipboard()
                    }
                    Button("Open Image File...") {
                        openImageFilePanel()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(StudioTheme.accent)
                        Text("Capture")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(StudioTheme.textPrimary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(StudioTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(StudioTheme.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Start a new screenshot capture")

                if let img = image {
                    let mult: CGFloat = state.showLogicalPoints ? 0.5 : 1.0
                    let unit = state.showLogicalPoints ? "pt" : "px"
                    Button(action: {
                        state.showLogicalPoints.toggle()
                        state.showToast(state.showLogicalPoints ? "Logical Points (1pt = 2px)" : "Physical Pixels")
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "aspectratio")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(StudioTheme.accent)
                            Text("\(Int(img.size.width * mult)) × \(Int(img.size.height * mult)) \(unit)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(StudioTheme.textPrimary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(StudioTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(StudioTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Click or press [P] to toggle Physical Pixels vs Logical Points")
                }

                // Live Eyedropper Color Swatch
                Menu {
                    ForEach(ColorCodeFormat.allCases) { fmt in
                        Button(fmt.rawValue) {
                            state.colorFormat = fmt
                            copyHoveredColor()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(nsColor: state.hoveredColor))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(StudioTheme.borderStrong, lineWidth: 1))
                        Text(ScreenCaptureManager.shared.formatColor(state.hoveredColor, format: state.colorFormat))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(StudioTheme.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 112, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(StudioTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(StudioTheme.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Hover over any pixel and press [Tab] to copy its color")

                StudioActionPill(
                    title: "",
                    systemIcon: "scope",
                    isPrimary: state.showLoupe
                ) {
                    state.showLoupe.toggle()
                    state.showToast(state.showLoupe ? "8× Pixel Magnifier Loupe ON" : "Pixel Magnifier Loupe OFF")
                }
                .help("Toggle Live 8× Pixel Magnifier Loupe")
            }

            Spacer()

            // Center: Studio App Controls (Library, Theme Mode, Keep-on-Top Toggle, Settings)
            HStack(spacing: 6) {
                StudioActionPill(title: "Library", systemIcon: "photo.on.rectangle.angled") {
                    NotificationCenter.default.post(name: Notification.Name("ScreenshotsOpenLibrary"), object: nil)
                }
                .help("Open Screenshot History & OCR Search")

                StudioActionPill(
                    title: theme.mode.rawValue,
                    systemIcon: theme.mode.icon
                ) {
                    theme.cycleMode()
                    state.showToast("Appearance: \(theme.mode.rawValue) Mode")
                }
                .help("Switch between Dark, Light, and System Auto Appearance")

                StudioActionPill(
                    title: "",
                    systemIcon: state.isFloatingWindow ? "macwindow.on.rectangle" : "macwindow",
                    isPrimary: state.isFloatingWindow
                ) {
                    state.isFloatingWindow.toggle()
                    state.showToast(state.isFloatingWindow ? "Window set to Float Above All Apps" : "Standard Window Mode (Can place behind other windows)")
                }
                .help(state.isFloatingWindow ? "Floating Above Apps (Click to return to Normal window level)" : "Normal Window Level (Click to keep window floating on top)")

                StudioActionPill(title: "", systemIcon: "gearshape.fill") {
                    NotificationCenter.default.post(name: Notification.Name("ScreenshotsOpenPreferences"), object: nil)
                }
                .help("Open Settings & Preferences (⌘,)")
            }

            Spacer()

            // Right: Studio Actions (Backdrop, Resize, Lift Subject, OCR, Pin, Drag-Out, Copy, Save)
            HStack(spacing: 6) {
                StudioActionPill(
                    title: "Backdrop",
                    systemIcon: "sparkles.rectangle.stack",
                    isPrimary: state.backdrop.mode != .none || state.showBackdropInspector
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        state.showBackdropInspector.toggle()
                    }
                }
                .help("Open Backdrop Studio (Gradients, Aspect Ratios, Window Header, Shadows)")

                StudioActionPill(title: "", systemIcon: "arrow.up.left.and.down.right") {
                    if let img = image {
                        state.targetWidthText = "\(Int(img.size.width))"
                        state.targetHeightText = "\(Int(img.size.height))"
                        state.showResizePopover.toggle()
                    }
                }
                .help("Resize or Scale Image")
                .popover(isPresented: $state.showResizePopover) {
                    resizePopoverContent
                }

                StudioActionPill(title: "", systemIcon: "person.crop.rectangle") {
                    liftSubjectAction()
                }
                .help("Remove Background / Lift Foreground Subject (Vision AI)")

                StudioActionPill(title: "OCR", systemIcon: "text.viewfinder") {
                    runOCR()
                }
                .help("Extract Text & QR Codes")

                StudioActionPill(title: "Pin", systemIcon: "pin.fill") {
                    pinCurrentImage()
                }
                .help("Create a Separate Mini Pinned Reference Window")

                if let img = image {
                    DraggableThumbnailButton(imageProvider: { renderFlattenedImage() ?? img })
                }

                StudioActionPill(title: "Copy", systemIcon: "doc.on.doc", isPrimary: true) {
                    copyToClipboard()
                }
                .help("Copy Rendered Image to Clipboard (⌘C)")

                StudioActionPill(title: "Save", systemIcon: "arrow.down.to.line") {
                    saveToDefaultFolder()
                }
                .help("Save Image to Folder (⌘S)")
            }
        }
        .padding(.leading, 78) // Safe inset so macOS traffic lights never overlap buttons
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(StudioTheme.bgBar)
    }

    // MARK: - Floating Contextual Style Pill (Above Bottom Dock)
    private var floatingContextualStylePill: some View {
        HStack(spacing: 12) {
            // Precision Color Swatches + Color Picker
            HStack(spacing: 5) {
                ForEach([
                    Color(red: 1.0, green: 0.24, blue: 0.19), // Coral Red
                    Color(red: 1.0, green: 0.58, blue: 0.0),  // Amber Orange
                    Color(red: 1.0, green: 0.84, blue: 0.04), // Highlighter Yellow
                    Color(red: 0.19, green: 0.82, blue: 0.35),// Emerald Green
                    Color(red: 0.04, green: 0.52, blue: 1.0), // System Blue
                    Color(red: 0.69, green: 0.32, blue: 0.87),// Royal Purple
                    Color.white,
                    Color(red: 0.12, green: 0.12, blue: 0.14)
                ], id: \.self) { swatch in
                    let isCurrent = state.strokeColor == swatch
                    Circle()
                        .fill(swatch)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(isCurrent ? StudioTheme.textPrimary : StudioTheme.borderStrong, lineWidth: isCurrent ? 2.0 : 1.0)
                        )
                        .scaleEffect(isCurrent ? 1.14 : 1.0)
                        .onTapGesture {
                            state.strokeColor = swatch
                            updateSelectedAnnotation { $0.color = swatch }
                        }
                }

                ColorPicker("", selection: $state.strokeColor)
                    .labelsHidden()
                    .frame(width: 20, height: 20)
            }

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 16)

            // Stroke Weight Slider
            HStack(spacing: 6) {
                Image(systemName: "lineweight")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(StudioTheme.textSecondary)
                Slider(value: $state.strokeWidth, in: 1.5...16)
                    .frame(width: 82)
                    .onChange(of: state.strokeWidth) { newVal in
                        updateSelectedAnnotation { $0.lineWidth = newVal }
                    }
                Text("\(Int(state.strokeWidth))px")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(StudioTheme.textSecondary)
                    .frame(width: 28, alignment: .leading)
            }

            // Contextual Tool Sub-Options
            if state.currentTool == .arrow {
                Rectangle().fill(StudioTheme.border).frame(width: 1, height: 16)
                StudioSegmentedPills(items: ArrowStyle.allCases, selection: $state.arrowStyle)
            } else if state.currentTool == .rect || state.currentTool == .oval {
                Rectangle().fill(StudioTheme.border).frame(width: 1, height: 16)
                StudioSegmentedPills(items: ShapeFillStyle.allCases, selection: $state.fillStyle)
            } else if state.currentTool == .conceal {
                Rectangle().fill(StudioTheme.border).frame(width: 1, height: 16)
                StudioSegmentedPills(items: ConcealMode.allCases, selection: $state.concealMode)
            } else if state.currentTool == .text {
                Rectangle().fill(StudioTheme.border).frame(width: 1, height: 16)
                StudioSegmentedPills(items: TextFontStyle.allCases, selection: $state.fontStyle)
            } else if state.currentTool == .line {
                Rectangle().fill(StudioTheme.border).frame(width: 1, height: 16)
                Toggle("Dashed", isOn: $state.isDashed)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(StudioTheme.textPrimary)
            }

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 16)

            // Selection / Undo / Redo / Clear
            HStack(spacing: 5) {
                if state.selectedItemID != nil {
                    StudioActionPill(title: "Delete", systemIcon: "trash.fill", isPrimary: true) {
                        state.deleteSelected()
                    }
                }

                StudioActionPill(title: "", systemIcon: "arrow.uturn.backward") {
                    state.undo()
                }
                .opacity(state.undoStack.isEmpty ? 0.4 : 1.0)
                .disabled(state.undoStack.isEmpty)
                .help("Undo (⌘Z)")

                StudioActionPill(title: "", systemIcon: "arrow.uturn.forward") {
                    state.redo()
                }
                .opacity(state.redoStack.isEmpty ? 0.4 : 1.0)
                .disabled(state.redoStack.isEmpty)
                .help("Redo (⇧⌘Z)")

                StudioActionPill(title: "Clear", systemIcon: "xmark.bin") {
                    guard !state.annotations.isEmpty else { return }
                    state.pushUndo()
                    state.annotations.removeAll()
                    state.selectedItemID = nil
                    state.counterStep = 1
                    state.showToast("Cleared all annotations")
                }
                .opacity(state.annotations.isEmpty ? 0.4 : 1.0)
                .disabled(state.annotations.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(StudioTheme.bgDock)
                .overlay(Capsule().stroke(StudioTheme.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        )
    }

    // MARK: - Bottom Floating Glass Instrument Dock (All 15 Custom Vector Tools)
    private var floatingBottomToolDock: some View {
        HStack(spacing: 3) {
            ForEach(ToolMode.allCases) { tool in
                StudioIconButton(
                    tool: tool,
                    isSelected: state.currentTool == tool,
                    action: {
                        state.currentTool = tool
                        if tool == .image {
                            pickOverlayImage()
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(StudioTheme.bgDock)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(StudioTheme.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        )
    }

    // MARK: - Zoom Control Pill
    private var zoomControlPill: some View {
        HStack(spacing: 4) {
            Button(action: { state.zoomScale = max(0.25, state.zoomScale - 0.25) }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: { state.zoomScale = 1.0 }) {
                Text("\(Int(state.zoomScale * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 44)
            }
            .buttonStyle(.plain)
            .help("Reset Zoom to 100% [0]")

            Button(action: { state.zoomScale = min(4.0, state.zoomScale + 0.25) }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(StudioTheme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(StudioTheme.bgDock)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(StudioTheme.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
    }

    // MARK: - Empty Workspace Welcome View
    private var emptyWorkspaceWelcomeView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(StudioTheme.accent.opacity(0.14))
                        .frame(width: 74, height: 74)
                    Image(nsImage: AppIconGenerator.makeAppIcon(size: 128))
                        .resizable()
                        .frame(width: 62, height: 62)
                        .shadow(color: StudioTheme.accent.opacity(0.35), radius: 14, y: 6)
                }
                Text("Screenshots Studio")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(StudioTheme.textPrimary)
                Text("Precision macOS Screen Capture, Annotation, OCR & Backdrop Engine")
                    .font(.system(size: 13))
                    .foregroundColor(StudioTheme.textSecondary)
            }

            HStack(spacing: 14) {
                WelcomeCaptureCard(
                    title: "Area Capture",
                    subtitle: "Drag crosshair over any region",
                    shortcut: "⌃ ⇧ 2",
                    icon: "viewfinder",
                    accentColor: StudioTheme.accent
                ) {
                    NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerArea"), object: nil)
                }

                WelcomeCaptureCard(
                    title: "Window Capture",
                    subtitle: "Snap any macOS window cleanly",
                    shortcut: "⌃ ⇧ W",
                    icon: "macwindow",
                    accentColor: Color(red: 0.20, green: 0.62, blue: 1.0)
                ) {
                    NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerWindow"), object: nil)
                }

                WelcomeCaptureCard(
                    title: "Scrolling Capture",
                    subtitle: "Auto-scroll & stitch tall pages",
                    shortcut: "⌃ ⇧ 3",
                    icon: "arrow.up.and.down.text.horizontal",
                    accentColor: Color(red: 0.68, green: 0.36, blue: 0.96)
                ) {
                    NotificationCenter.default.post(name: Notification.Name("ScreenshotsTriggerScrolling"), object: nil)
                }

                WelcomeCaptureCard(
                    title: "Text & QR OCR",
                    subtitle: "Extract text or scan QR codes",
                    shortcut: "⌃ ⇧ O",
                    icon: "qrcode.viewfinder",
                    accentColor: Color(red: 0.18, green: 0.82, blue: 0.48)
                ) {
                    ScreenCaptureManager.shared.captureInteractiveArea { captured in
                        guard let captured = captured else { return }
                        self.image = captured
                        runOCR()
                    }
                }
            }

            HStack(spacing: 12) {
                StudioActionPill(title: "Paste from Clipboard (⌘V)", systemIcon: "doc.on.clipboard") {
                    loadFromClipboard()
                }
                StudioActionPill(title: "Open Image File...", systemIcon: "folder") {
                    openImageFilePanel()
                }
                StudioActionPill(title: "Load Interactive Demo Canvas", systemIcon: "wand.and.stars", isPrimary: true) {
                    self.image = makeDemoSampleScreenshot()
                    state.showToast("Loaded interactive sample canvas")
                }
            }
        }
        .padding(34)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(StudioTheme.bgBar.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioTheme.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 28, y: 10)
        )
        .padding(.bottom, 76)
    }

    private func floatingTextEntryHUD(at pt: CGPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "textformat")
                    .foregroundColor(StudioTheme.accent)
                Text("Add Text Callout")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(StudioTheme.textPrimary)
            }
            TextField("Type text and press Return...", text: $state.textDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(StudioTheme.textPrimary)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(StudioTheme.bgCanvas))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(StudioTheme.borderStrong, lineWidth: 1))
                .frame(width: 260)
                .onSubmit { commitTextAnnotation(at: pt) }
            HStack {
                Spacer()
                StudioActionPill(title: "Cancel", systemIcon: "xmark") {
                    state.pendingTextPoint = nil
                }
                StudioActionPill(title: "Insert", systemIcon: "checkmark", isPrimary: true) {
                    commitTextAnnotation(at: pt)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(StudioTheme.bgBar)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(StudioTheme.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        )
    }

    // MARK: - Rendered Canvas + Backdrop Studio Composition (with Window Frame & Aspect Ratios)
    @ViewBuilder
    private func renderedCanvasView(for img: NSImage) -> some View {
        let screenshotCard = VStack(spacing: 0) {
            if state.backdrop.mode != .none && state.backdrop.showWindowHeader {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 11, height: 11)
                    Circle().fill(Color(red: 0.15, green: 0.78, blue: 0.25)).frame(width: 11, height: 11)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(width: img.size.width, height: 30)
                .background(Color(red: 0.12, green: 0.13, blue: 0.16))
            }

            Image(nsImage: img)
                .resizable()
                .frame(width: img.size.width, height: img.size.height)
                .overlay(
                    CanvasInteractiveOverlay(
                        image: $image,
                        state: state
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: state.backdrop.mode == .none ? 0 : state.backdrop.innerRadius))
        .shadow(
            color: Color.black.opacity(state.backdrop.mode == .none ? 0.25 : 0.45),
            radius: state.backdrop.mode == .none ? 12 : state.backdrop.shadowRadius,
            x: 0,
            y: state.backdrop.mode == .none ? 5 : 12
        )

        if state.backdrop.mode == .none {
            screenshotCard
        } else {
            let baseW = img.size.width + state.backdrop.padding * 2
            let baseH = img.size.height + (state.backdrop.showWindowHeader ? 30 : 0) + state.backdrop.padding * 2
            let framedSize = computeAspectSize(baseWidth: baseW, baseHeight: baseH, aspect: state.backdrop.aspect)

            ZStack {
                backdropBackgroundView
                screenshotCard
            }
            .frame(width: framedSize.width, height: framedSize.height)
            .clipShape(RoundedRectangle(cornerRadius: state.backdrop.outerRadius))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        }
    }

    private func computeAspectSize(baseWidth: CGFloat, baseHeight: CGFloat, aspect: AspectPreset) -> CGSize {
        guard let targetRatio = aspect.ratio else {
            return CGSize(width: baseWidth, height: baseHeight)
        }
        let currentRatio = baseWidth / max(1, baseHeight)
        if currentRatio > targetRatio {
            return CGSize(width: baseWidth, height: round(baseWidth / targetRatio))
        } else {
            return CGSize(width: round(baseHeight * targetRatio), height: baseHeight)
        }
    }

    @ViewBuilder
    private var backdropBackgroundView: some View {
        switch state.backdrop.mode {
        case .none:
            EmptyView()
        case .solid:
            Rectangle().fill(state.backdrop.solidColor)
        case .colormix, .mesh:
            switch state.backdrop.gradientDirection {
            case .diagonal:
                LinearGradient(
                    colors: [state.backdrop.colorFrom, state.backdrop.colorTo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .vertical:
                LinearGradient(
                    colors: [state.backdrop.colorFrom, state.backdrop.colorTo],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .radial:
                RadialGradient(
                    colors: [state.backdrop.colorFrom, state.backdrop.colorTo],
                    center: .center,
                    startRadius: 10,
                    endRadius: 520
                )
            }
        }
    }

    private var resizePopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resize / Scale Image")
                .font(.system(size: 13, weight: .bold))
            HStack(spacing: 6) {
                TextField("Width", text: $state.targetWidthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
                Text("×")
                TextField("Height", text: $state.targetHeightText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
                Text("px")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                ForEach([("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("200%", 2.0)], id: \.0) { label, scale in
                    Button(label) {
                        if let img = image {
                            resizeImage(to: NSSize(width: round(img.size.width * scale), height: round(img.size.height * scale)))
                            state.showResizePopover = false
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button("Apply Dimensions") {
                if let w = Double(state.targetWidthText), let h = Double(state.targetHeightText), w > 10, h > 10 {
                    resizeImage(to: NSSize(width: w, height: h))
                    state.showResizePopover = false
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    // MARK: - Single-Key Shortcuts Handler
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if state.pendingTextPoint != nil { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""

        if flags.contains(.command) {
            if chars == "C" {
                copyToClipboard()
                return true
            } else if chars == "S" {
                saveToDefaultFolder()
                return true
            } else if chars == "V" {
                loadFromClipboard()
                return true
            } else if chars == "," {
                NotificationCenter.default.post(name: Notification.Name("ScreenshotsOpenPreferences"), object: nil)
                return true
            } else if chars == "Z" {
                if flags.contains(.shift) {
                    state.redo()
                } else {
                    state.undo()
                }
                return true
            }
            return false
        }

        // Delete / Backspace removes selected annotation
        if event.keyCode == 51 || event.keyCode == 117 {
            if state.selectedItemID != nil {
                state.deleteSelected()
                return true
            }
        }

        // Tab copies pixel color under cursor
        if event.keyCode == 48 {
            copyHoveredColor()
            return true
        }

        switch chars {
        case "V": state.currentTool = .select; return true
        case "C": state.currentTool = .crop; return true
        case "A": state.currentTool = .arrow; return true
        case "F": state.currentTool = .freehand; return true
        case "H": state.currentTool = .highlighter; return true
        case "L": state.currentTool = .line; return true
        case "R": state.currentTool = .rect; return true
        case "O": state.currentTool = .oval; return true
        case "T": state.currentTool = .text; return true
        case "N": state.currentTool = .counter; return true
        case "S": state.currentTool = .spotlight; return true
        case "M": state.currentTool = .magnifier; return true
        case "B": state.currentTool = .conceal; return true
        case "U": state.currentTool = .ruler; return true
        case "P":
            state.showLogicalPoints.toggle()
            state.showToast(state.showLogicalPoints ? "Logical Points (1pt = 2px)" : "Physical Pixels")
            return true
        case "0":
            state.zoomScale = 1.0
            return true
        default:
            return false
        }
    }

    private func updateSelectedAnnotation(_ transform: (inout AnnotationItem) -> Void) {
        guard let id = state.selectedItemID,
              let idx = state.annotations.firstIndex(where: { $0.id == id }) else { return }
        transform(&state.annotations[idx])
    }

    // MARK: - Editor Actions
    private func openImageFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let loaded = NSImage(contentsOf: url) {
            self.image = loaded
        }
    }

    private func commitTextAnnotation(at pt: CGPoint) {
        defer {
            state.pendingTextPoint = nil
            state.textDraft = ""
        }
        guard !state.textDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.pushUndo()
        let item = AnnotationItem(
            tool: .text,
            startPoint: pt,
            endPoint: CGPoint(x: pt.x + 180, y: pt.y + 36),
            color: state.strokeColor,
            lineWidth: state.strokeWidth,
            text: state.textDraft,
            fontStyle: state.fontStyle
        )
        state.annotations.append(item)
        state.selectedItemID = item.id
    }

    private func pickOverlayImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let overImg = NSImage(contentsOf: url) {
            state.pushUndo()
            let item = AnnotationItem(
                tool: .image,
                startPoint: CGPoint(x: 60, y: 60),
                endPoint: CGPoint(x: 60 + min(320, overImg.size.width), y: 60 + min(240, overImg.size.height)),
                overlayNSImage: overImg
            )
            state.annotations.append(item)
            state.selectedItemID = item.id
            state.showToast("Added overlay image")
        }
    }

    private func liftSubjectAction() {
        guard let img = image else { return }
        state.showToast("Isolating foreground subject with Vision AI...")
        ScreenCaptureManager.shared.removeBackground(from: img) { out in
            if let out = out {
                self.image = out
                self.state.showToast("Background removed!")
            } else {
                self.state.showToast("Could not isolate a distinct subject")
            }
        }
    }

    private func resizeImage(to newSize: NSSize) {
        guard let img = image else { return }
        let newImg = NSImage(size: newSize)
        newImg.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: img.size), operation: .copy, fraction: 1.0)
        newImg.unlockFocus()
        self.image = newImg
        state.showToast("Resized to \(Int(newSize.width)) × \(Int(newSize.height))")
    }

    private func copyHoveredColor() {
        let formatted = ScreenCaptureManager.shared.formatColor(state.hoveredColor, format: state.colorFormat)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(formatted, forType: .string)
        state.showToast("Copied \(formatted)")
    }

    private func runOCR() {
        guard let img = image else { return }
        let removeBreaks = UserDefaults.standard.bool(forKey: "ocrRemoveBreaks")
        ScreenCaptureManager.shared.recognizeTextAndQR(in: img, removeLineBreaks: removeBreaks) { text in
            self.state.ocrResultText = text
            self.state.showingOcrAlert = true
        }
    }

    private func pinCurrentImage() {
        guard let finalImg = renderFlattenedImage() else { return }
        PinWindowManager.shared.pinImage(finalImg) { edited in
            self.image = edited
        }
        state.showToast("Pinned floating window")
    }

    private func copyToClipboard() {
        guard let finalImg = renderFlattenedImage() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([finalImg])
        state.showToast("Copied rendered image to clipboard")
    }

    private func saveToDefaultFolder() {
        guard let finalImg = renderFlattenedImage(),
              let tiff = finalImg.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }

        let folder = ScreenCaptureManager.shared.defaultSaveFolder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SCR-\(formatter.string(from: Date())).png"
        let fileURL = folder.appendingPathComponent(filename)
        try? png.write(to: fileURL)
        state.showToast("Saved \(filename)")
    }

    private func loadFromClipboard() {
        let pb = NSPasteboard.general
        if let copiedImg = NSImage(pasteboard: pb) {
            self.image = copiedImg
            state.annotations.removeAll()
            state.selectedItemID = nil
            state.showToast("Loaded image from clipboard")
        }
    }

    @MainActor
    private func renderFlattenedImage() -> NSImage? {
        guard let img = image else { return nil }
        let savedSelection = state.selectedItemID
        let savedLoupe = state.showLoupe
        state.selectedItemID = nil
        state.showLoupe = false
        let renderer = ImageRenderer(content: renderedCanvasView(for: img))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let output = renderer.nsImage ?? img
        state.selectedItemID = savedSelection
        state.showLoupe = savedLoupe
        return output
    }

    private func makeDemoSampleScreenshot() -> NSImage {
        let size = NSSize(width: 860, height: 500)
        let img = NSImage(size: size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colors = [
                CGColor(srgbRed: 0.10, green: 0.12, blue: 0.18, alpha: 1.0),
                CGColor(srgbRed: 0.16, green: 0.20, blue: 0.30, alpha: 1.0)
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 0.95))
            let card = CGRect(x: 65, y: 55, width: 730, height: 390)
            ctx.addPath(CGPath(roundedRect: card, cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.fillPath()

            let dots: [(CGFloat, CGColor)] = [
                (95, CGColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1)),
                (117, CGColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1)),
                (139, CGColor(srgbRed: 0.15, green: 0.78, blue: 0.25, alpha: 1))
            ]
            for (dx, clr) in dots {
                ctx.setFillColor(clr)
                ctx.fillEllipse(in: CGRect(x: dx, y: 412, width: 12, height: 12))
            }

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(srgbRed: 0.65, green: 0.82, blue: 1.0, alpha: 1.0)
            ]
            NSString(string: "Screenshots Studio — Ready for Annotation & OCR").draw(at: NSPoint(x: 95, y: 345), withAttributes: titleAttr)
            NSString(string: "• Pick any tool in the Floating Glass Dock below\n• Drag corner handles on any shape to resize it interactively\n• Drag Pixelate / Smart Erase [B] over API_SECRET_KEY = \"sk_live_984729384\"\n• Click 'Backdrop' to wrap in gradients, aspect ratios & window headers").draw(in: NSRect(x: 95, y: 135, width: 660, height: 190), withAttributes: bodyAttr)
        }
        img.unlockFocus()
        return img
    }
}

// MARK: - Studio Welcome Capture Card
struct WelcomeCaptureCard: View {
    let title: String
    let subtitle: String
    let shortcut: String
    let icon: String
    let accentColor: Color
    let action: () -> Void
    @StateObject private var hover = HoverState()
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    Spacer()
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(StudioTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(StudioTheme.bgCanvas))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(StudioTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(StudioTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(width: 195, height: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hover.isHovered ? StudioTheme.surfaceHover : StudioTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hover.isHovered ? accentColor.opacity(0.6) : StudioTheme.border, lineWidth: 1)
            )
            .scaleEffect(hover.isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.14), value: hover.isHovered)
        }
        .buttonStyle(.plain)
        .onHover { h in hover.isHovered = h }
    }
}

// MARK: - Drag-Out File Handle
struct DraggableThumbnailButton: View {
    let imageProvider: () -> NSImage
    @StateObject private var hover = HoverState()
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Drag")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(StudioTheme.textPrimary)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(hover.isHovered ? StudioTheme.surfaceHover : StudioTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(StudioTheme.border, lineWidth: 1))
        .onHover { h in hover.isHovered = h }
        .help("Drag and drop this handle directly into Finder, Slack, Messages, or Mail")
        .onDrag {
            let img = imageProvider()
            let tempURL = URL(fileURLWithPath: "/tmp/Screenshots_Drop_\(Int(Date().timeIntervalSince1970)).png")
            if let tiff = img.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                try? png.write(to: tempURL)
            }
            return NSItemProvider(contentsOf: tempURL) ?? NSItemProvider(object: img)
        }
    }
}

// MARK: - Backdrop Studio Sidebar Inspector (with Aspect Ratios & macOS Window Frame)
struct BackdropStudioSidebar: View {
    @Binding var config: BackdropConfig
    let onClose: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Backdrop Studio", systemImage: "sparkles.rectangle.stack")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(StudioTheme.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(StudioTheme.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(StudioTheme.surface))
                    }
                    .buttonStyle(.plain)
                }

                StudioSegmentedPills(items: BackdropMode.allCases, selection: $config.mode)

                HStack(spacing: 6) {
                    StudioActionPill(title: "Randomize", systemIcon: "dice.fill", isPrimary: true) {
                        if let preset = BackdropConfig.presets.randomElement() {
                            config.mode = .colormix
                            config.colorFrom = preset.1
                            config.colorTo = preset.2
                        }
                    }
                    StudioActionPill(title: "Swap ⇄", systemIcon: "arrow.left.arrow.right") {
                        let tmp = config.colorFrom
                        config.colorFrom = config.colorTo
                        config.colorTo = tmp
                    }
                    StudioActionPill(title: "Reset", systemIcon: "arrow.counterclockwise") {
                        config = BackdropConfig()
                    }
                }

                if config.mode != .none {
                    Divider().background(StudioTheme.border)

                    if config.mode == .solid {
                        ColorPicker("Solid Color:", selection: $config.solidColor)
                            .font(.system(size: 12))
                            .foregroundColor(StudioTheme.textPrimary)
                    } else {
                        Text("GRADIENT PRESETS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(StudioTheme.textMuted)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                            ForEach(0..<BackdropConfig.presets.count, id: \.self) { idx in
                                let preset = BackdropConfig.presets[idx]
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [preset.1, preset.2], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(height: 32)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.24), lineWidth: 1))
                                    Text(preset.0)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(StudioTheme.textSecondary)
                                }
                                .onTapGesture {
                                    config.mode = .colormix
                                    config.colorFrom = preset.1
                                    config.colorTo = preset.2
                                }
                            }
                        }

                        HStack {
                            ColorPicker("Start:", selection: $config.colorFrom)
                            Spacer()
                            ColorPicker("End:", selection: $config.colorTo)
                        }
                        .font(.system(size: 11.5))
                        .foregroundColor(StudioTheme.textPrimary)

                        StudioSegmentedPills(items: GradientDirection.allCases, selection: $config.gradientDirection)
                    }

                    Divider().background(StudioTheme.border)

                    Text("ASPECT RATIO & FRAME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(StudioTheme.textMuted)

                    StudioSegmentedPills(items: AspectPreset.allCases, selection: $config.aspect)

                    Toggle("Add macOS Window Header Bar", isOn: $config.showWindowHeader)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(StudioTheme.textPrimary)

                    Divider().background(StudioTheme.border)

                    VStack(alignment: .leading, spacing: 10) {
                        BackdropSliderRow(label: "Padding", value: $config.padding, range: 12...140)
                        BackdropSliderRow(label: "Drop Shadow", value: $config.shadowRadius, range: 0...60)
                        BackdropSliderRow(label: "Inner Radius", value: $config.innerRadius, range: 0...36)
                        BackdropSliderRow(label: "Outer Radius", value: $config.outerRadius, range: 0...48)
                    }
                } else {
                    Text("Pick Gradient, Mesh, or Solid—or click Randomize—to wrap your capture in a presentation frame with social aspect ratios.")
                        .font(.system(size: 11.5))
                        .foregroundColor(StudioTheme.textSecondary)
                        .padding(.top, 6)
                }
            }
            .padding(16)
        }
        .frame(width: 292)
        .background(StudioTheme.bgBar)
    }
}

struct BackdropSliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(StudioTheme.textSecondary)
                Spacer()
                Text("\(Int(value))px")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(StudioTheme.textPrimary)
            }
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Adaptive Dot Grid Studio Background
struct StudioCanvasGridBackground: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(StudioTheme.bgCanvas))
            let spacing: CGFloat = 24
            let dotColor = theme.isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.065)
            for x in stride(from: spacing, to: size.width, by: spacing) {
                for y in stride(from: spacing, to: size.height, by: spacing) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(dotColor))
                }
            }
        }
    }
}

// MARK: - Interactive Canvas Overlay (Draggable Corner Resize Handles + Live 8x Loupe + All 15 Tools)
struct CanvasInteractiveOverlay: View {
    @Binding var image: NSImage?
    @ObservedObject var state: EditorState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Spotlight dimming layer if any spotlight annotation exists
                let spotlights = state.annotations.filter { $0.tool == .spotlight } +
                    (state.activeItem?.tool == .spotlight ? [state.activeItem!] : [])

                if !spotlights.isEmpty {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        for sp in spotlights {
                            path.addRoundedRect(in: sp.boundingRect, cornerSize: CGSize(width: 8, height: 8))
                        }
                    }
                    .fill(Color.black.opacity(0.65), style: FillStyle(eoFill: true))
                }

                // Render committed annotations + interactive draggable corner resize handles
                ForEach(state.annotations) { item in
                    let isSelected = state.selectedItemID == item.id
                    renderObject(item, in: geo.size)
                        .overlay(
                            Group {
                                if isSelected && ![.counter, .freehand, .highlighter, .text].contains(item.tool) {
                                    SelectionHandlesOverlay(item: item, onResize: { handlePos, newPoint in
                                        resizeSelectedAnnotation(id: item.id, handle: handlePos, to: newPoint)
                                    }, onEnd: {
                                        state.dragStartSnapshot = nil
                                    })
                                }
                            }
                        )
                }

                // Render active dragging annotation
                if let active = state.activeItem {
                    renderObject(active, in: geo.size)
                }

                // Live 8x Pixel Grid Magnifier Loupe when active
                if state.showLoupe && state.isHoveringCanvas, let img = image {
                    PixelLoupeOverlayView(
                        image: img,
                        cursorLocation: state.hoverLocation,
                        canvasSize: geo.size,
                        sampledColor: state.hoveredColor
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    state.isHoveringCanvas = true
                    state.hoverLocation = loc
                    if let img = image, geo.size.width > 0, geo.size.height > 0 {
                        let norm = CGPoint(x: loc.x / geo.size.width, y: loc.y / geo.size.height)
                        state.hoveredColor = ScreenCaptureManager.shared.sampleColor(in: img, at: norm)
                    }
                case .ended:
                    state.isHoveringCanvas = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if state.currentTool == .select {
                            if state.dragStartSnapshot == nil {
                                if let hit = hitTestAnnotation(at: value.startLocation) {
                                    state.selectedItemID = hit.id
                                    state.dragStartSnapshot = hit
                                    state.pushUndo()
                                } else {
                                    state.selectedItemID = nil
                                }
                            }
                            if let snap = state.dragStartSnapshot,
                               let idx = state.annotations.firstIndex(where: { $0.id == snap.id }) {
                                let dx = value.translation.width
                                let dy = value.translation.height
                                state.annotations[idx].startPoint = CGPoint(x: snap.startPoint.x + dx, y: snap.startPoint.y + dy)
                                state.annotations[idx].endPoint = CGPoint(x: snap.endPoint.x + dx, y: snap.endPoint.y + dy)
                                state.annotations[idx].points = snap.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                            }
                            return
                        }

                        if state.currentTool == .text || state.currentTool == .counter {
                            return
                        }
                        if state.activeItem == nil {
                            state.activeItem = AnnotationItem(
                                tool: state.currentTool,
                                startPoint: value.startLocation,
                                endPoint: value.location,
                                points: [value.startLocation, value.location],
                                color: state.strokeColor,
                                lineWidth: state.strokeWidth,
                                counterIndex: state.counterStep,
                                arrowStyle: state.arrowStyle,
                                fillStyle: state.fillStyle,
                                concealMode: state.concealMode,
                                fontStyle: state.fontStyle,
                                isDashed: state.isDashed
                            )
                        } else {
                            state.activeItem?.endPoint = value.location
                            state.activeItem?.points.append(value.location)
                        }
                    }
                    .onEnded { value in
                        if state.currentTool == .select {
                            state.dragStartSnapshot = nil
                            return
                        }
                        if state.currentTool == .text {
                            state.pendingTextPoint = value.location
                            return
                        }
                        if state.currentTool == .counter {
                            state.pushUndo()
                            let item = AnnotationItem(
                                tool: .counter,
                                startPoint: value.location,
                                endPoint: value.location,
                                color: state.strokeColor,
                                counterIndex: state.counterStep
                            )
                            state.annotations.append(item)
                            state.selectedItemID = item.id
                            state.counterStep += 1
                            return
                        }
                        if state.currentTool == .crop, let active = state.activeItem {
                            performCrop(rect: active.boundingRect, canvasSize: geo.size)
                            state.activeItem = nil
                            return
                        }
                        if var item = state.activeItem {
                            let dragDist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                            if dragDist < 4, let hit = hitTestAnnotation(at: value.location) {
                                state.selectedItemID = hit.id
                                state.activeItem = nil
                                return
                            }
                            item.endPoint = value.location
                            state.pushUndo()
                            state.annotations.append(item)
                            state.selectedItemID = item.id
                            state.activeItem = nil
                        }
                    }
            )
        }
    }

    private func resizeSelectedAnnotation(id: UUID, handle: ResizeHandlePosition, to pt: CGPoint) {
        guard let idx = state.annotations.firstIndex(where: { $0.id == id }) else { return }
        if state.dragStartSnapshot == nil {
            state.dragStartSnapshot = state.annotations[idx]
            state.pushUndo()
        }
        let r = state.annotations[idx].boundingRect
        switch handle {
        case .topLeft:
            state.annotations[idx].startPoint = pt
            state.annotations[idx].endPoint = CGPoint(x: r.maxX, y: r.maxY)
        case .topRight:
            state.annotations[idx].startPoint = CGPoint(x: r.minX, y: pt.y)
            state.annotations[idx].endPoint = CGPoint(x: pt.x, y: r.maxY)
        case .bottomLeft:
            state.annotations[idx].startPoint = CGPoint(x: pt.x, y: r.minY)
            state.annotations[idx].endPoint = CGPoint(x: r.maxX, y: pt.y)
        case .bottomRight:
            state.annotations[idx].startPoint = CGPoint(x: r.minX, y: r.minY)
            state.annotations[idx].endPoint = pt
        }
    }

    private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
        for item in state.annotations.reversed() {
            let expanded = item.boundingRect.insetBy(dx: -12, dy: -12)
            if expanded.contains(point) {
                return item
            }
        }
        return nil
    }

    private func performCrop(rect: CGRect, canvasSize: CGSize) {
        guard let img = image, rect.width > 12, rect.height > 12 else { return }
        let scaleX = img.size.width / canvasSize.width
        let scaleY = img.size.height / canvasSize.height
        let cropRect = NSRect(
            x: rect.minX * scaleX,
            y: (canvasSize.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        let cropped = NSImage(size: cropRect.size)
        cropped.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: cropRect.size), from: cropRect, operation: .copy, fraction: 1.0)
        cropped.unlockFocus()
        self.image = cropped
        state.annotations.removeAll()
        state.selectedItemID = nil
        state.showToast("Cropped to \(Int(cropRect.width)) × \(Int(cropRect.height))")
    }

    @ViewBuilder
    private func renderObject(_ item: AnnotationItem, in canvasSize: CGSize) -> some View {
        let rect = item.boundingRect

        switch item.tool {
        case .arrow:
            ArrowShape(start: item.startPoint, end: item.endPoint, style: item.arrowStyle)
                .stroke(item.color, style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)

        case .line:
            Path { path in
                path.move(to: item.startPoint)
                path.addLine(to: item.endPoint)
            }
            .stroke(
                item.color,
                style: StrokeStyle(
                    lineWidth: item.lineWidth,
                    lineCap: .round,
                    dash: item.isDashed ? [8, 6] : []
                )
            )

        case .freehand:
            Path { path in
                guard let first = item.points.first else { return }
                path.move(to: first)
                for pt in item.points.dropFirst() {
                    path.addLine(to: pt)
                }
            }
            .stroke(item.color, style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))

        case .highlighter:
            Path { path in
                guard let first = item.points.first else { return }
                path.move(to: first)
                for pt in item.points.dropFirst() {
                    path.addLine(to: pt)
                }
            }
            .stroke(item.color.opacity(0.42), style: StrokeStyle(lineWidth: max(20, item.lineWidth * 5.5), lineCap: .square))
            .blendMode(.multiply)

        case .rect:
            ZStack {
                if item.fillStyle == .opaque {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(item.color)
                } else if item.fillStyle == .translucent {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(item.color.opacity(0.22))
                }
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        item.color,
                        style: StrokeStyle(
                            lineWidth: item.lineWidth,
                            dash: item.fillStyle == .sketch ? [10, 4] : []
                        )
                    )
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

        case .oval:
            ZStack {
                if item.fillStyle == .opaque {
                    Ellipse().fill(item.color)
                } else if item.fillStyle == .translucent {
                    Ellipse().fill(item.color.opacity(0.22))
                }
                Ellipse().stroke(item.color, lineWidth: item.lineWidth)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

        case .conceal:
            RealImageConcealView(
                sourceImage: image,
                region: rect,
                canvasSize: canvasSize,
                mode: item.concealMode
            )
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .position(x: rect.midX, y: rect.midY)

        case .counter:
            ZStack {
                Circle()
                    .fill(item.color)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                Text("\(item.counterIndex)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .position(item.startPoint)

        case .text:
            let fontDesign: Font.Design = item.fontStyle == .mono ? .monospaced : (item.fontStyle == .rounded ? .rounded : .default)
            Text(item.text)
                .font(.system(size: max(15, item.lineWidth * 5.2), weight: .bold, design: fontDesign))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(item.color)
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                )
                .position(item.startPoint)

        case .magnifier:
            ZStack {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: canvasSize.width * 2.0, height: canvasSize.height * 2.0)
                        .offset(
                            x: (canvasSize.width / 2 - rect.midX) * 2.0,
                            y: (canvasSize.height / 2 - rect.midY) * 2.0
                        )
                }
            }
            .frame(width: max(90, rect.width), height: max(90, rect.height))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .overlay(Circle().stroke(item.color, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .position(x: rect.midX, y: rect.midY)

        case .ruler:
            let dist = hypot(item.endPoint.x - item.startPoint.x, item.endPoint.y - item.startPoint.y)
            let mult: CGFloat = state.showLogicalPoints ? 0.5 : 1.0
            let unit = state.showLogicalPoints ? "pt" : "px"
            ZStack {
                Path { path in
                    path.move(to: item.startPoint)
                    path.addLine(to: item.endPoint)
                }
                .stroke(item.color, lineWidth: 2)

                Circle().fill(item.color).frame(width: 7, height: 7).position(item.startPoint)
                Circle().fill(item.color).frame(width: 7, height: 7).position(item.endPoint)

                Text("\(Int(round(dist * mult))) \(unit)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(item.color))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(x: (item.startPoint.x + item.endPoint.x) / 2, y: (item.startPoint.y + item.endPoint.y) / 2 - 16)
            }

        case .crop:
            ZStack {
                Rectangle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .background(StudioTheme.accent.opacity(0.10))
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

        case .image:
            if let overImg = item.overlayNSImage {
                Image(nsImage: overImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: rect.width, height: rect.height)
                    .shadow(radius: 8)
                    .position(x: rect.midX, y: rect.midY)
            }

        case .spotlight, .select:
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.65), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

// MARK: - Interactive Draggable 4-Corner Resize Knobs Overlay
struct SelectionHandlesOverlay: View {
    let item: AnnotationItem
    let onResize: (ResizeHandlePosition, CGPoint) -> Void
    let onEnd: () -> Void

    var body: some View {
        let r = item.boundingRect
        let handles: [(ResizeHandlePosition, CGPoint)] = [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY))
        ]

        ZStack {
            Rectangle()
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: r.width + 4, height: r.height + 4)
                .position(x: r.midX, y: r.midY)

            ForEach(0..<handles.count, id: \.self) { idx in
                let pos = handles[idx].0
                let pt = handles[idx].1
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(StudioTheme.accent, lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .position(pt)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                onResize(pos, drag.location)
                            }
                            .onEnded { _ in onEnd() }
                    )
            }
        }
    }
}

// MARK: - Live 8x Pixel Magnifier Loupe Overlay
struct PixelLoupeOverlayView: View {
    let image: NSImage
    let cursorLocation: CGPoint
    let canvasSize: CGSize
    let sampledColor: NSColor

    var body: some View {
        let loupeSize: CGFloat = 116
        ZStack {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: canvasSize.width * 6.0, height: canvasSize.height * 6.0)
                .offset(
                    x: (canvasSize.width / 2 - cursorLocation.x) * 6.0,
                    y: (canvasSize.height / 2 - cursorLocation.y) * 6.0
                )

            // Center crosshair reticle
            Rectangle()
                .stroke(StudioTheme.accent, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
        .frame(width: loupeSize, height: loupeSize)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        .overlay(alignment: .bottom) {
            Text(ScreenCaptureManager.shared.formatColor(sampledColor, format: .hex))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .offset(y: 12)
        }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .position(
            x: min(max(70, cursorLocation.x + 68), canvasSize.width - 70),
            y: max(70, cursorLocation.y - 68)
        )
    }
}

// MARK: - Real CoreImage Pixelate / Blur / Smart Erase Filter
struct RealImageConcealView: View {
    let sourceImage: NSImage?
    let region: CGRect
    let canvasSize: CGSize
    let mode: ConcealMode

    var body: some View {
        if let img = sourceImage {
            switch mode {
            case .smartErase:
                let norm = CGPoint(
                    x: max(0.01, min(0.99, region.minX / max(1, canvasSize.width))),
                    y: max(0.01, min(0.99, region.minY / max(1, canvasSize.height)))
                )
                let sampled = ScreenCaptureManager.shared.sampleColor(in: img, at: norm)
                Rectangle()
                    .fill(Color(nsColor: sampled))
            case .blur:
                Image(nsImage: img)
                    .resizable()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .blur(radius: 14)
                    .offset(
                        x: canvasSize.width / 2 - region.midX,
                        y: canvasSize.height / 2 - region.midY
                    )
            case .pixelate:
                if let pixelated = Self.makePixelatedImage(from: img) {
                    Image(nsImage: pixelated)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .offset(
                            x: canvasSize.width / 2 - region.midX,
                            y: canvasSize.height / 2 - region.midY
                        )
                } else {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .blur(radius: 12)
                        .offset(
                            x: canvasSize.width / 2 - region.midX,
                            y: canvasSize.height / 2 - region.midY
                        )
                }
            }
        }
    }

    private static func makePixelatedImage(from image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let ciInput = CIImage(data: tiff) else { return nil }
        let filter = CIFilter.pixellate()
        filter.inputImage = ciInput
        filter.scale = 16.0
        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let out = NSImage(size: image.size)
        out.addRepresentation(rep)
        return out
    }
}

// MARK: - Local Keyboard Monitor Bridge
struct KeyboardEventMonitorView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    final class Coordinator {
        var monitor: Any?
        var handler: ((NSEvent) -> Bool)?
        deinit {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.handler = onKeyDown
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak coordinator] event in
            // Only act for the editor window, and never while the user is typing in a text field.
            guard let window = view?.window, event.window === window else { return event }
            if window.firstResponder is NSTextView { return event }
            if coordinator?.handler?(event) == true { return nil }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = onKeyDown
    }
}

// MARK: - Vector Arrow Renderer (Single, Curved, Double)
struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let style: ArrowStyle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let headLength: CGFloat = 17.0
        let headAngle: CGFloat = .pi / 6

        if style == .curved {
            let mid = CGPoint(
                x: (start.x + end.x) / 2 + CGFloat(-dy * 0.14),
                y: (start.y + end.y) / 2 + CGFloat(dx * 0.14)
            )
            path.move(to: start)
            path.addQuadCurve(to: end, control: mid)
        } else {
            path.move(to: start)
            path.addLine(to: end)
        }

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)

        if style == .double {
            let s1 = CGPoint(
                x: start.x + headLength * cos(angle - headAngle),
                y: start.y + headLength * sin(angle - headAngle)
            )
            let s2 = CGPoint(
                x: start.x + headLength * cos(angle + headAngle),
                y: start.y + headLength * sin(angle + headAngle)
            )
            path.move(to: start)
            path.addLine(to: s1)
            path.move(to: start)
            path.addLine(to: s2)
        }

        return path
    }
}
