#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Screenshots"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$HOME/Applications/${APP_NAME}.app"
SYS_BUNDLE_DIR="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.screenshots.studio"

echo "🔨 Building ${APP_NAME} (Release)..."
cd "$ROOT"
swift build -c release

echo "📦 Packaging ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp -f ".build/release/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

if [ -f "$ROOT/AppIcon.icns" ]; then
    cp -f "$ROOT/AppIcon.icns" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
fi

cat > "${BUNDLE_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.0</string>
    <key>CFBundleVersion</key>
    <string>230</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Screenshots needs Screen Recording access to capture your screen.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.tiff</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

printf 'APPL????' > "${BUNDLE_DIR}/Contents/PkgInfo"

echo "🔏 Signing with stable designated requirement (no cdhash invalidation)..."
codesign --force --deep -s - -i "${BUNDLE_ID}" --requirement "=designated => identifier \"${BUNDLE_ID}\"" "${BUNDLE_DIR}"

if [ -w "/Applications" ]; then
    echo "📲 Installing to ${SYS_BUNDLE_DIR}..."
    rm -rf "${SYS_BUNDLE_DIR}"
    cp -R "${BUNDLE_DIR}" "${SYS_BUNDLE_DIR}"
    codesign --force --deep -s - -i "${BUNDLE_ID}" --requirement "=designated => identifier \"${BUNDLE_ID}\"" "${SYS_BUNDLE_DIR}"
fi

echo "✅ Installed cleanly to ${SYS_BUNDLE_DIR}"
