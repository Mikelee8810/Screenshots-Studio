import AppKit

/// Editor tools, in toolbar order (mirrors Shottr's editor).
enum Tool: String, CaseIterable {
    case select
    case arrow
    case line
    case rectangle
    case roundedRect
    case ellipse
    case counter
    case text
    case highlight
    case pen
    case blur
    case pixelate
    case crop

    var title: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .roundedRect: return "Rounded Rectangle"
        case .ellipse: return "Ellipse"
        case .counter: return "Step Counter"
        case .text: return "Text"
        case .highlight: return "Highlighter"
        case .pen: return "Pen"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .crop: return "Crop"
        }
    }

    /// Preferred SF Symbol; EditorWindowController falls back to `fallbackGlyph` if unavailable.
    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .roundedRect: return "rectangle.roundedtop"
        case .ellipse: return "circle"
        case .counter: return "number.circle"
        case .text: return "character"
        case .highlight: return "highlighter"
        case .pen: return "scribble.variable"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .crop: return "crop"
        }
    }

    var fallbackGlyph: String {
        switch self {
        case .select: return "▲"
        case .arrow: return "↗"
        case .line: return "╱"
        case .rectangle: return "▭"
        case .roundedRect: return "▢"
        case .ellipse: return "◯"
        case .counter: return "①"
        case .text: return "T"
        case .highlight: return "▍"
        case .pen: return "✎"
        case .blur: return "░"
        case .pixelate: return "▦"
        case .crop: return "⌗"
        }
    }

    /// Single-key shortcut in the editor.
    var shortcut: String {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .roundedRect: return "o"
        case .ellipse: return "e"
        case .counter: return "c"
        case .text: return "t"
        case .highlight: return "h"
        case .pen: return "p"
        case .blur: return "b"
        case .pixelate: return "x"
        case .crop: return "k"
        }
    }

    /// Tools that produce a draggable shape from start→end.
    var isDragShape: Bool {
        switch self {
        case .arrow, .line, .rectangle, .roundedRect, .ellipse, .highlight, .blur, .pixelate, .crop:
            return true
        case .select, .counter, .text, .pen:
            return false
        }
    }
}
