#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Screenshots"
BUNDLE_DIR="$HOME/Applications/${APP_NAME}.app"
SYS_BUNDLE_DIR="/Applications/${APP_NAME}.app"

echo "🔨 Building ${APP_NAME} (Release)..."
swift build -c release

echo "📦 Packaging ${BUNDLE_DIR}..."
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp -f ".build/release/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${BUNDLE_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.screenshots.studio</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Screenshots Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.2.0</string>
    <key>CFBundleVersion</key>
    <string>220</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${BUNDLE_DIR}"

if [ -w "/Applications" ]; then
    rm -rf "${SYS_BUNDLE_DIR}" 2>/dev/null || true
    cp -R "${BUNDLE_DIR}" "${SYS_BUNDLE_DIR}" 2>/dev/null || true
fi

echo "✅ Installed to ${BUNDLE_DIR}"
echo "🚀 Launching ${APP_NAME}..."
killall "${APP_NAME}" 2>/dev/null || true
open "${BUNDLE_DIR}"
