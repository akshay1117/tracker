#!/bin/bash
set -euo pipefail

# MacPulse Native macOS Application Bundle Builder
echo "=== Building MacPulse Release Binary ==="

export DEVELOPER_DIR="/Library/Developer/CommandLineTools"

# 1. Compile in Release mode
swift build -c release

RELEASE_BIN=".build/release/MacPulse"
APP_NAME="MacPulse.app"
APP_DIR="${APP_NAME}/Contents"
MACOS_DIR="${APP_DIR}/MacOS"
RESOURCES_DIR="${APP_DIR}/Resources"

echo "=== Assembling ${APP_NAME} Bundle ==="
rm -rf "${APP_NAME}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 2. Copy binary and resources
cp "${RELEASE_BIN}" "${MACOS_DIR}/MacPulse"
chmod +x "${MACOS_DIR}/MacPulse"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 3. Create Info.plist
cat << 'EOF' > "${APP_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacPulse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.macpulse.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacPulse</string>
    <key>CFBundleDisplayName</key>
    <string>MacPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

# 4. Create PkgInfo
echo -n "APPL????" > "${APP_DIR}/PkgInfo"

# 5. Ad-hoc codesign the bundle
echo "=== Signing ${APP_NAME} (Ad-Hoc) ==="
codesign --force --deep --sign - "${APP_NAME}"

echo "=== Build Successful: ${APP_NAME} is ready! ==="
ls -ld "${APP_NAME}"
