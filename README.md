# Screenshots Studio (`Screenshots.app`)

A fast, native macOS screen capture, annotation, OCR, and presentation studio built with Swift & SwiftUI.

## ✨ Highlights & Features

- **Standard Window Level + Optional Float Mode**: Behaves like a normal macOS window by default (can be placed behind any window), with a one-click header toggle if you want it floating above other apps.
- **Adaptive Light, Dark & Auto Theme**: Instant toggle in the header bar or Settings (`⌘,`).
- **Floating Bottom Glass Dock**:
  - **15 Custom Vector Instruments**: Select/Move (`V`), Crop (`C`), Arrow (`A` — Single, Curved, Double), Rectangle (`R` — Outline, Glass, Solid, Dashed), Oval (`O`), Line (`L`), Freehand (`F`), Highlighter (`H`), Text Callout (`T`), Step Counter (`N`), Pixelate / Blur / Smart Text Erase (`B`), Spotlight (`S`), Magnifier Lens (`M`), Pixel Ruler (`U`), and Overlay Image (`I`).
  - **Interactive 4-Corner Resize Handles**: Click any drawn object to move it or drag any of its 4 corner knobs to resize live.
- **Capture Modes**:
  - Interactive Area (`⌃⇧2`), Repeat Last Area (`⌃⇧R`), Fullscreen (`⌃⇧1`), Any Window (`⌃⇧W`), Active Window (`⌃⇧A`), Scrolling Capture Down/Up (`⌃⇧3` / `⌃⇧4`), and 3-Second Delayed Capture (`⌃⇧D`).
- **Apple Vision AI Engine**:
  - Instant **Text & QR Code OCR** (`⌃⇧O`).
  - One-click **Foreground Subject Lift / Background Removal**.
- **Live 8× Pixel Magnifier Loupe & Eyedropper**:
  - Toggle the `8×` pixel loupe in the top bar and press `Tab` to copy colors in `HEX`, `CSS rgba`, `SwiftUI Color`, `NSColor`, `Android`, `C#`, or `OKLCH`.
- **Backdrop Studio**:
  - Wrap screenshots in gradients, mesh presets, or solid cards with customizable padding, drop shadows, inner/outer corner radii, **macOS traffic-light window header bars**, and social aspect ratios (`Auto`, `16:9`, `4:3`, `1:1`, `X / Post`).
- **Pin Reference Windows**:
  - Pin floating borderless screenshots anywhere on screen with **X-Ray semi-transparency** mode.

- **Screen Recording & GIF**: Record your display to MP4 (ScreenCaptureKit, ⌃⇧5 by default) and convert any recording to a looping GIF from the menu bar.
- **Customizable global shortcuts**: Click any shortcut in Settings → Shortcuts and press a new combo.
- **Real macOS menus** (App / File / Edit / Window), launch at login, first-run Screen Recording permission check, and a proper app icon.

## 🚀 Quick Build & Run on Any Mac

```bash
git clone https://github.com/Mikelee8810/Screenshots-Studio.git
cd Screenshots-Studio
chmod +x build_app.sh
./build_app.sh
```
