import SwiftUI
import AppKit

// MARK: - App Appearance Mode (Light, Dark, System)

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case system = "Auto"
    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Core Tool & Mode Enums

public enum ToolMode: String, CaseIterable, Identifiable {
    case select = "Select / Move"
    case crop = "Crop"
    case arrow = "Arrow"
    case rect = "Rectangle"
    case oval = "Oval"
    case line = "Line"
    case freehand = "Freehand"
    case highlighter = "Highlighter"
    case text = "Text"
    case counter = "Step Counter"
    case conceal = "Blur / Redact"
    case spotlight = "Spotlight"
    case magnifier = "Magnifier"
    case ruler = "Pixel Ruler"
    case image = "Overlay Image"
    case backdrop = "Backdrop Studio"
    case append = "Append Screenshot"

    public var id: String { rawValue }

    public var shortcutKey: String {
        switch self {
        case .select: return "V"
        case .crop: return "C"
        case .arrow: return "A"
        case .rect: return "R"
        case .oval: return "O"
        case .line: return "L"
        case .freehand: return "F"
        case .highlighter: return "H"
        case .text: return "T"
        case .counter: return "N"
        case .conceal: return "B"
        case .spotlight: return "S"
        case .magnifier: return "M"
        case .ruler: return "U"
        case .image: return "I"
        case .backdrop: return "K"
        case .append: return "⇧⌘A"
        }
    }

    /// The exact 15 instrument tools matching Shottr's toolbarInstruments
    public static var shottrInstruments: [ToolMode] {
        [
            .arrow,
            .text,
            .ruler,
            .rect,
            .backdrop,
            .freehand,
            .magnifier,
            .append,
            .conceal,
            .highlighter,
            .spotlight,
            .counter,
            .oval,
            .line,
            .image
        ]
    }
}

public enum ArrowStyle: String, CaseIterable, Identifiable, Sendable {
    case single = "Single"
    case curved = "Curved"
    case double = "Double"
    public var id: String { rawValue }
}

public enum ShapeFillStyle: String, CaseIterable, Identifiable, Sendable {
    case transparent = "Outline"
    case translucent = "Glass"
    case opaque = "Solid"
    case sketch = "Dashed"
    public var id: String { rawValue }
}

public enum ConcealMode: String, CaseIterable, Identifiable, Sendable {
    case pixelate = "Pixelate"
    case blur = "Blur"
    case smartErase = "Smart Erase"
    public var id: String { rawValue }
}

public enum TextFontStyle: String, CaseIterable, Identifiable, Sendable {
    case sans = "Sans"
    case mono = "Code"
    case rounded = "Rounded"
    public var id: String { rawValue }
}

public enum ColorCodeFormat: String, CaseIterable, Identifiable, Sendable {
    case hex = "HEX (#FF3B30)"
    case cssRgba = "CSS rgba(255, 59, 48, 1)"
    case swiftUI = "Color(red: 1.00, green: 0.23, blue: 0.19)"
    case nsColor = "UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1.00)"
    case android = "Android 0xFFFF3B30"
    case csharp = "Color.fromArgb(255, 59, 48);"
    case oklch = "oklch(62.8% 0.25 29.2)"
    public var id: String { rawValue }
}

// MARK: - Backdrop Studio & Social Aspect Ratio Presets

public enum BackdropMode: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case colormix = "Gradient"
    case mesh = "Mesh"
    case solid = "Solid"
    public var id: String { rawValue }
}

public enum GradientDirection: String, CaseIterable, Identifiable, Sendable {
    case diagonal = "Diagonal"
    case vertical = "Vertical"
    case radial = "Radial"
    public var id: String { rawValue }
}

public enum AspectPreset: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case wide16x9 = "16:9"
    case standard4x3 = "4:3"
    case square1x1 = "1:1"
    case twitter = "X / Post"
    public var id: String { rawValue }

    public var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .wide16x9: return 16.0 / 9.0
        case .standard4x3: return 4.0 / 3.0
        case .square1x1: return 1.0
        case .twitter: return 1.91
        }
    }
}

public struct BackdropConfig: Equatable {
    public var mode: BackdropMode = .none
    public var gradientDirection: GradientDirection = .diagonal
    public var colorFrom: Color = Color(red: 0.08, green: 0.30, blue: 0.68)
    public var colorTo: Color = Color(red: 0.36, green: 0.78, blue: 1.0)
    public var solidColor: Color = Color(red: 0.12, green: 0.14, blue: 0.20)
    public var padding: CGFloat = 52
    public var shadowRadius: CGFloat = 26
    public var outerRadius: CGFloat = 18
    public var innerRadius: CGFloat = 10
    public var showWindowHeader: Bool = false
    public var aspect: AspectPreset = .auto

    public static let presets: [(String, Color, Color)] = [
        ("Ocean", Color(red: 0.05, green: 0.16, blue: 0.44), Color(red: 0.24, green: 0.76, blue: 0.98)),
        ("Sunset", Color(red: 0.98, green: 0.24, blue: 0.38), Color(red: 1.0, green: 0.68, blue: 0.20)),
        ("Hyper", Color(red: 0.42, green: 0.16, blue: 0.88), Color(red: 0.94, green: 0.26, blue: 0.76)),
        ("Emerald", Color(red: 0.05, green: 0.58, blue: 0.46), Color(red: 0.42, green: 0.92, blue: 0.64)),
        ("Noir", Color(red: 0.10, green: 0.11, blue: 0.15), Color(red: 0.24, green: 0.27, blue: 0.35)),
        ("Amber", Color(red: 0.92, green: 0.38, blue: 0.10), Color(red: 0.99, green: 0.80, blue: 0.22)),
        ("Aurora", Color(red: 0.10, green: 0.18, blue: 0.45), Color(red: 0.68, green: 0.24, blue: 0.72)),
        ("Ice", Color(red: 0.76, green: 0.88, blue: 0.98), Color(red: 0.92, green: 0.96, blue: 1.0))
    ]
}

// MARK: - Canvas Annotation Object

public enum ResizeHandlePosition: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public struct AnnotationItem: Identifiable, Equatable {
    public let id: UUID
    public var tool: ToolMode
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var points: [CGPoint]
    public var color: Color
    public var lineWidth: CGFloat
    public var text: String
    public var counterIndex: Int
    public var arrowStyle: ArrowStyle
    public var fillStyle: ShapeFillStyle
    public var concealMode: ConcealMode
    public var fontStyle: TextFontStyle
    public var isDashed: Bool
    public var overlayNSImage: NSImage?

    public init(
        id: UUID = UUID(),
        tool: ToolMode,
        startPoint: CGPoint,
        endPoint: CGPoint,
        points: [CGPoint] = [],
        color: Color = Color(red: 1.0, green: 0.24, blue: 0.19),
        lineWidth: CGFloat = 3.5,
        text: String = "",
        counterIndex: Int = 1,
        arrowStyle: ArrowStyle = .single,
        fillStyle: ShapeFillStyle = .transparent,
        concealMode: ConcealMode = .pixelate,
        fontStyle: TextFontStyle = .sans,
        isDashed: Bool = false,
        overlayNSImage: NSImage? = nil
    ) {
        self.id = id
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.counterIndex = counterIndex
        self.arrowStyle = arrowStyle
        self.fillStyle = fillStyle
        self.concealMode = concealMode
        self.fontStyle = fontStyle
        self.isDashed = isDashed
        self.overlayNSImage = overlayNSImage
    }

    public var boundingRect: CGRect {
        if tool == .counter {
            return CGRect(x: startPoint.x - 16, y: startPoint.y - 16, width: 32, height: 32)
        }
        return CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: max(abs(endPoint.x - startPoint.x), 8),
            height: max(abs(endPoint.y - startPoint.y), 8)
        )
    }
}

public struct LibraryScreenshotItem: Identifiable {
    public let id: UUID = UUID()
    public let url: URL
    public let date: Date
    public let dimensions: CGSize
    public let fileSize: Int64
    public var ocrIndexedText: String
}
