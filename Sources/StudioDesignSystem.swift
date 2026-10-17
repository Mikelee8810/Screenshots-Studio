import SwiftUI
import AppKit

// MARK: - Adaptive Theme Controller (Light, Dark & System Mode)

public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    @Published public var mode: AppearanceMode = {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.dark.rawValue
        return AppearanceMode(rawValue: raw) ?? .dark
    }() {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
            applyWindowAppearance()
        }
    }

    @Published public var isDark: Bool = true

    private init() {
        applyWindowAppearance()
    }

    public func cycleMode() {
        switch mode {
        case .dark: mode = .light
        case .light: mode = .system
        case .system: mode = .dark
        }
    }

    public func applyWindowAppearance() {
        switch mode {
        case .dark:
            isDark = true
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case .light:
            isDark = false
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .system:
            let sysDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            isDark = sysDark
            NSApplication.shared.appearance = nil
        }
    }

    public var colorScheme: ColorScheme {
        isDark ? .dark : .light
    }
}

// MARK: - Adaptive Studio Palette

public enum StudioTheme {
    private static var dark: Bool { ThemeManager.shared.isDark }

    public static var bgCanvas: Color {
        dark ? Color(red: 0.075, green: 0.08, blue: 0.098) : Color(red: 0.93, green: 0.94, blue: 0.96)
    }
    public static var bgBar: Color {
        dark ? Color(red: 0.115, green: 0.122, blue: 0.145) : Color(red: 0.985, green: 0.988, blue: 0.995)
    }
    public static var bgDock: Color {
        dark ? Color(red: 0.13, green: 0.14, blue: 0.17).opacity(0.92) : Color.white.opacity(0.92)
    }
    public static var surface: Color {
        dark ? Color(red: 0.165, green: 0.175, blue: 0.205) : Color(red: 0.94, green: 0.948, blue: 0.965)
    }
    public static var surfaceHover: Color {
        dark ? Color(red: 0.215, green: 0.228, blue: 0.265) : Color(red: 0.89, green: 0.905, blue: 0.93)
    }
    public static var surfaceActive: Color {
        Color(red: 1.0, green: 0.24, blue: 0.19).opacity(dark ? 0.22 : 0.15)
    }
    public static let accent = Color(red: 1.0, green: 0.24, blue: 0.19)
    public static let accentBright = Color(red: 1.0, green: 0.34, blue: 0.26)

    public static var border: Color {
        dark ? Color.white.opacity(0.085) : Color.black.opacity(0.085)
    }
    public static var borderStrong: Color {
        dark ? Color.white.opacity(0.17) : Color.black.opacity(0.15)
    }
    public static var textPrimary: Color {
        dark ? Color.white.opacity(0.95) : Color(red: 0.09, green: 0.10, blue: 0.13)
    }
    public static var textSecondary: Color {
        dark ? Color.white.opacity(0.58) : Color(red: 0.38, green: 0.41, blue: 0.47)
    }
    public static var textMuted: Color {
        dark ? Color.white.opacity(0.36) : Color(red: 0.56, green: 0.59, blue: 0.65)
    }
}

// MARK: - Custom Vector Tool Icons

public struct CustomToolIcon: View {
    public let tool: ToolMode
    public let isSelected: Bool
    @ObservedObject private var theme = ThemeManager.shared

    public init(tool: ToolMode, isSelected: Bool) {
        self.tool = tool
        self.isSelected = isSelected
    }

    public var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let fg: Color = isSelected ? StudioTheme.accent : StudioTheme.textPrimary
            let stroke = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)

            switch tool {
            case .select:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.26, y: h * 0.18))
                p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.78))
                p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.62))
                p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.84))
                p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.78))
                p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.56))
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.54))
                p.closeSubpath()
                ctx.fill(p, with: .color(fg))

            case .crop:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.28, y: h * 0.14))
                p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.72))
                p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.72))
                p.move(to: CGPoint(x: w * 0.14, y: h * 0.28))
                p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.28))
                p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.86))
                ctx.stroke(p, with: .color(fg), style: stroke)

            case .arrow:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.20, y: h * 0.80))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
                p.move(to: CGPoint(x: w * 0.44, y: h * 0.22))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.56))
                ctx.stroke(p, with: .color(fg), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

            case .freehand:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.16, y: h * 0.72))
                p.addCurve(
                    to: CGPoint(x: w * 0.84, y: h * 0.28),
                    control1: CGPoint(x: w * 0.36, y: h * 0.10),
                    control2: CGPoint(x: w * 0.62, y: h * 0.90)
                )
                ctx.stroke(p, with: .color(fg), style: stroke)

            case .highlighter:
                var bodyPath = Path()
                bodyPath.addRoundedRect(in: CGRect(x: w * 0.20, y: h * 0.36, width: w * 0.60, height: h * 0.28), cornerSize: CGSize(width: 3, height: 3))
                ctx.fill(bodyPath, with: .color(fg.opacity(0.35)))
                ctx.stroke(bodyPath, with: .color(fg), style: stroke)

            case .line:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.18, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.18))
                ctx.stroke(p, with: .color(fg), style: stroke)
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.18 - 2.5, y: h * 0.82 - 2.5, width: 5, height: 5)), with: .color(fg))
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.82 - 2.5, y: h * 0.18 - 2.5, width: 5, height: 5)), with: .color(fg))

            case .rect:
                let r = CGRect(x: w * 0.18, y: h * 0.24, width: w * 0.64, height: h * 0.52)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3.5), with: .color(fg), style: stroke)

            case .oval:
                let r = CGRect(x: w * 0.18, y: h * 0.22, width: w * 0.64, height: h * 0.56)
                ctx.stroke(Path(ellipseIn: r), with: .color(fg), style: stroke)

            case .text:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.22, y: h * 0.24))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.24))
                p.move(to: CGPoint(x: w * 0.50, y: h * 0.24))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.80))
                p.move(to: CGPoint(x: w * 0.36, y: h * 0.80))
                p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.80))
                ctx.stroke(p, with: .color(fg), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))

            case .counter:
                let circleRect = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64)
                ctx.fill(Path(ellipseIn: circleRect), with: .color(fg))
                var one = Path()
                one.move(to: CGPoint(x: w * 0.44, y: h * 0.38))
                one.addLine(to: CGPoint(x: w * 0.52, y: h * 0.32))
                one.addLine(to: CGPoint(x: w * 0.52, y: h * 0.68))
                ctx.stroke(one, with: .color(theme.isDark ? Color.black : Color.white), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

            case .spotlight:
                let outer = CGRect(x: w * 0.16, y: h * 0.20, width: w * 0.68, height: h * 0.60)
                ctx.fill(Path(roundedRect: outer, cornerRadius: 4), with: .color(fg.opacity(0.28)))
                let inner = CGRect(x: w * 0.34, y: h * 0.34, width: w * 0.38, height: h * 0.34)
                ctx.stroke(Path(roundedRect: inner, cornerRadius: 2.5), with: .color(fg), style: stroke)

            case .magnifier:
                let lens = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.48, height: h * 0.48)
                ctx.stroke(Path(ellipseIn: lens), with: .color(fg), style: stroke)
                var handle = Path()
                handle.move(to: CGPoint(x: w * 0.60, y: h * 0.60))
                handle.addLine(to: CGPoint(x: w * 0.82, y: h * 0.82))
                ctx.stroke(handle, with: .color(fg), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            case .conceal:
                let cell: CGFloat = w * 0.16
                let startX = w * 0.18
                let startY = h * 0.22
                for row in 0..<3 {
                    for col in 0..<4 {
                        if (row + col) % 2 == 0 {
                            let r = CGRect(x: startX + CGFloat(col) * cell, y: startY + CGFloat(row) * cell, width: cell, height: cell)
                            ctx.fill(Path(r), with: .color(fg))
                        } else {
                            let r = CGRect(x: startX + CGFloat(col) * cell, y: startY + CGFloat(row) * cell, width: cell, height: cell)
                            ctx.fill(Path(r), with: .color(fg.opacity(0.28)))
                        }
                    }
                }

            case .ruler:
                let r = CGRect(x: w * 0.14, y: h * 0.34, width: w * 0.72, height: h * 0.32)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 2.5), with: .color(fg), style: stroke)
                var ticks = Path()
                for i in 1...3 {
                    let tx = w * 0.14 + CGFloat(i) * (w * 0.18)
                    ticks.move(to: CGPoint(x: tx, y: h * 0.34))
                    ticks.addLine(to: CGPoint(x: tx, y: h * 0.50))
                }
                ctx.stroke(ticks, with: .color(fg), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

            case .image:
                let r = CGRect(x: w * 0.16, y: h * 0.22, width: w * 0.68, height: h * 0.56)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3.5), with: .color(fg), style: stroke)
                var mtn = Path()
                mtn.move(to: CGPoint(x: w * 0.22, y: h * 0.70))
                mtn.addLine(to: CGPoint(x: w * 0.42, y: h * 0.46))
                mtn.addLine(to: CGPoint(x: w * 0.58, y: h * 0.62))
                mtn.addLine(to: CGPoint(x: w * 0.70, y: h * 0.50))
                mtn.addLine(to: CGPoint(x: w * 0.78, y: h * 0.70))
                ctx.stroke(mtn, with: .color(fg), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 19, height: 19)
    }
}

// MARK: - Studio Interactive Button Chrome

public final class HoverState: ObservableObject {
    @Published public var isHovered: Bool = false
    public init() {}
}

public struct StudioIconButton: View {
    let tool: ToolMode
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var hover = HoverState()
    @ObservedObject private var theme = ThemeManager.shared

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                CustomToolIcon(tool: tool, isSelected: isSelected)
                    .frame(width: 36, height: 34)

                Text(tool.shortcutKey)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? StudioTheme.accent : StudioTheme.textMuted)
                    .padding(.trailing, 3.5)
                    .padding(.bottom, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? StudioTheme.surfaceActive : (hover.isHovered ? StudioTheme.surfaceHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? StudioTheme.accent.opacity(0.7) : (hover.isHovered ? StudioTheme.borderStrong : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in hover.isHovered = h }
        .help("\(tool.rawValue) [\(tool.shortcutKey)]")
    }
}

public struct StudioActionPill: View {
    let title: String
    let systemIcon: String
    var isPrimary: Bool = false
    var badge: String? = nil
    let action: () -> Void
    @StateObject private var hover = HoverState()
    @ObservedObject private var theme = ThemeManager.shared

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if !systemIcon.isEmpty {
                    Image(systemName: systemIcon)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .foregroundColor(isPrimary ? .white : StudioTheme.textPrimary)
            .padding(.horizontal, title.isEmpty ? 8 : 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isPrimary
                            ? (hover.isHovered ? StudioTheme.accentBright : StudioTheme.accent)
                            : (hover.isHovered ? StudioTheme.surfaceHover : StudioTheme.surface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isPrimary ? Color.white.opacity(0.22) : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in hover.isHovered = h }
    }
}

public struct StudioSegmentedPills<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    let items: [T]
    @Binding var selection: T
    @ObservedObject private var theme = ThemeManager.shared

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let active = selection == item
                Button(action: { selection = item }) {
                    Text(item.rawValue)
                        .font(.system(size: 10.5, weight: active ? .bold : .medium))
                        .foregroundColor(active ? .white : StudioTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(active ? StudioTheme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(StudioTheme.bgCanvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Programmatic App Icon Generator

public enum AppIconGenerator {
    public static func makeAppIcon(size: CGFloat = 512) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let rect = CGRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88)
        let path = CGPath(roundedRect: rect, cornerWidth: size * 0.20, cornerHeight: size * 0.20, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        let colors = [
            CGColor(srgbRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.0),
            CGColor(srgbRed: 0.06, green: 0.065, blue: 0.09, alpha: 1.0)
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        }

        ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 0.24, blue: 0.19, alpha: 1.0))
        ctx.setLineWidth(size * 0.055)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let m = size * 0.22
        let b = size * 0.16

        ctx.move(to: CGPoint(x: m, y: size - m - b))
        ctx.addLine(to: CGPoint(x: m, y: size - m))
        ctx.addLine(to: CGPoint(x: m + b, y: size - m))

        ctx.move(to: CGPoint(x: size - m - b, y: size - m))
        ctx.addLine(to: CGPoint(x: size - m, y: size - m))
        ctx.addLine(to: CGPoint(x: size - m, y: size - m - b))

        ctx.move(to: CGPoint(x: m, y: m + b))
        ctx.addLine(to: CGPoint(x: m, y: m))
        ctx.addLine(to: CGPoint(x: m + b, y: m))

        ctx.move(to: CGPoint(x: size - m - b, y: m))
        ctx.addLine(to: CGPoint(x: size - m, y: m))
        ctx.addLine(to: CGPoint(x: size - m, y: m + b))
        ctx.strokePath()

        ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
        ctx.setLineWidth(size * 0.05)
        ctx.move(to: CGPoint(x: size * 0.36, y: size * 0.36))
        ctx.addLine(to: CGPoint(x: size * 0.64, y: size * 0.64))
        ctx.move(to: CGPoint(x: size * 0.46, y: size * 0.64))
        ctx.addLine(to: CGPoint(x: size * 0.64, y: size * 0.64))
        ctx.addLine(to: CGPoint(x: size * 0.64, y: size * 0.46))
        ctx.strokePath()

        img.unlockFocus()
        return img
    }

    public static func makeMenuBarIcon() -> NSImage {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }
        ctx.setStrokeColor(NSColor.labelColor.cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let m: CGFloat = 2.5
        let b: CGFloat = 4.2
        ctx.move(to: CGPoint(x: m, y: size - m - b))
        ctx.addLine(to: CGPoint(x: m, y: size - m))
        ctx.addLine(to: CGPoint(x: m + b, y: size - m))

        ctx.move(to: CGPoint(x: size - m - b, y: size - m))
        ctx.addLine(to: CGPoint(x: size - m, y: size - m))
        ctx.addLine(to: CGPoint(x: size - m, y: size - m - b))

        ctx.move(to: CGPoint(x: m, y: m + b))
        ctx.addLine(to: CGPoint(x: m, y: m))
        ctx.addLine(to: CGPoint(x: m + b, y: m))

        ctx.move(to: CGPoint(x: size - m - b, y: m))
        ctx.addLine(to: CGPoint(x: size - m, y: m))
        ctx.addLine(to: CGPoint(x: size - m, y: m + b))

        ctx.strokePath()
        ctx.fillEllipse(in: CGRect(x: size / 2 - 2, y: size / 2 - 2, width: 4, height: 4))

        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
