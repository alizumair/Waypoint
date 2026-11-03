#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "⚡ Building Waypoint macOS Menu Bar App"
echo "=========================================="

# 1. Compile Release Binary using Swift Package Manager
echo "🔨 Compiling Swift binary in release mode..."
swift build -c release

# 2. Locate built executable
BUILD_BIN="$(swift build -c release --show-bin-path)/Waypoint"

# 3. Setup .app Bundle Structure
APP_NAME="Waypoint.app"
BUNDLE_DIR="./$APP_NAME"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Assembling $APP_NAME bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 4. Copy Executable, Info.plist, and Icon
cp "$BUILD_BIN" "$MACOS_DIR/Waypoint"
cp "Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 5. Ad-hoc Codesign
echo "✍️  Ad-hoc codesigning $APP_NAME..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "✅ Build Successful! Application created at: $BUNDLE_DIR"
echo "👉 Launch with: open ./$APP_NAME"
