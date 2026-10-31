import AppKit
import Carbon.HIToolbox

// Lightweight assertion harness (no XCTest bundle needed under Command Line Tools).
var failures = 0
var passes = 0
func check(_ cond: Bool, _ name: String) {
    if cond { passes += 1 }
    else { failures += 1; FileHandle.standardError.write("FAIL: \(name)\n".data(using: .utf8)!) }
}
func approx(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.001) -> Bool { abs(a - b) < eps }

@main
struct TestRunner {
    static func main() {
        // HotkeySpec Codable round-trip
        let spec = HotkeySpec(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        let data = try! JSONEncoder().encode(["area": spec])
        let back = try! JSONDecoder().decode([String: HotkeySpec].self, from: data)
        check(back["area"] == spec, "HotkeySpec Codable round-trip")

        // KeyCodes display strings
        check(KeyCodes.displayString(spec) == "⇧⌘2", "displayString ⇧⌘2 == \(KeyCodes.displayString(spec))")
        check(KeyCodes.modifierString(UInt32(controlKey | optionKey | shiftKey | cmdKey)) == "⌃⌥⇧⌘", "modifier order")
        check(KeyCodes.carbonModifiers(from: [.command, .shift]) == UInt32(cmdKey | shiftKey), "carbonModifiers mapping")
        check(KeyCodes.isModifierKey(UInt16(kVK_Shift)), "isModifierKey shift")
        check(!KeyCodes.isModifierKey(UInt16(kVK_ANSI_2)), "isModifierKey not digit")

        // Coordinates round-trip (independent of primary height)
        let ak = CGRect(x: 100, y: 200, width: 300, height: 150)
        let cg = Coordinates.cgTopLeftRect(fromAppKit: ak)
        let akBack = Coordinates.appKitRect(fromCGTopLeft: cg)
        check(approx(akBack.minX, ak.minX) && approx(akBack.minY, ak.minY) &&
              approx(akBack.width, ak.width) && approx(akBack.height, ak.height), "Coordinates AppKit<->CG round-trip")

        // NSColor hex
        check(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).hexString == "#FF0000", "hex red")
        check(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).hexString == "#000000", "hex black")

        // Annotation geometry
        let a = Annotation(kind: .rectangle, color: .red, lineWidth: 4,
                           start: CGPoint(x: 10, y: 60), end: CGPoint(x: 110, y: 10))
        check(approx(a.rect.minX, 10) && approx(a.rect.minY, 10) &&
              approx(a.rect.width, 100) && approx(a.rect.height, 50), "rect normalization")
        check(a.handlePositions().count == 4, "rect has 4 handles")
        a.resize(handleIndex: 2, to: CGPoint(x: 200, y: 120))
        // Top-left corner (10,10) stays fixed; bottom-right moves to (200,120) => 190×110.
        check(approx(a.rect.width, 190) && approx(a.rect.height, 110) && approx(a.rect.minX, 10) && approx(a.rect.minY, 10),
              "resize keeps opposite corner fixed")
        let before = a.rect
        a.translate(by: CGVector(dx: 5, dy: -3))
        check(approx(a.rect.minX, before.minX + 5) && approx(a.rect.minY, before.minY - 3), "translate")

        let line = Annotation(kind: .line, color: .red, lineWidth: 3,
                              start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        check(line.hitTest(CGPoint(x: 50, y: 2), tolerance: 5), "line hit near")
        check(!line.hitTest(CGPoint(x: 50, y: 40), tolerance: 5), "line miss far")
        check(line.handlePositions().count == 2, "line has 2 endpoint handles")

        // Annotation copy is deep (undo safety)
        let c = Annotation(kind: .arrow, color: .blue, lineWidth: 2, start: .zero, end: CGPoint(x: 10, y: 10))
        let d = c.copy()
        d.translate(by: CGVector(dx: 100, dy: 0))
        check(approx(c.end.x, 10) && approx(d.end.x, 110), "copy is independent (undo safety)")

        // Demo annotations cover all kinds
        let demo = AnnotationRenderer.demoAnnotations(pointSize: NSSize(width: 800, height: 600))
        let kinds = Set(demo.map { "\($0.kind)" })
        let expected: [Annotation.Kind] = [.rectangle, .roundedRect, .ellipse, .arrow, .line, .highlight, .blur, .pixelate, .pen, .counter, .text]
        let missing = expected.filter { !kinds.contains("\($0)") }
        check(missing.isEmpty, "demo covers all kinds (missing: \(missing))")
        let counters = demo.filter { $0.kind == .counter }.map { $0.number }.sorted()
        check(counters == [1, 2], "demo counters numbered 1,2")

        // Config hotkey set + conflict detection
        let cfg = Config.shared
        cfg.setHotkey(HotkeySpec(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | optionKey), enabled: true), for: .area)
        check(cfg.hotkeys[.area]?.keyCode == UInt32(kVK_ANSI_9), "setHotkey persists in memory")
        check(HotkeyManager.shared.conflictingAction(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | optionKey), excluding: .window) == .area,
              "conflict detection finds area")
        check(HotkeyManager.shared.conflictingAction(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | optionKey), excluding: .area) == nil,
              "conflict excludes self")

        // Tool shortcuts are unique
        let shortcuts = Tool.allCases.map { $0.shortcut }
        check(Set(shortcuts).count == shortcuts.count, "tool shortcuts unique")

        print("\nScreenshots tests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
