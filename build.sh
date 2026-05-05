#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GhostLocation"
APP_BUNDLE="$DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🏗  Building $APP_NAME..."

# Clean previous build
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy Info.plist
cp "$DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Collect all Swift sources
SOURCES=("$DIR"/Sources/*.swift)

# Compile
swiftc "${SOURCES[@]}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework MapKit \
    -framework CoreLocation \
    -framework Foundation \
    -target arm64-apple-macosx14.0 \
    -O \
    -module-name GhostLocation \
    -Xfrontend -enable-experimental-feature -Xfrontend StrictConcurrency \
    -o "$MACOS_DIR/$APP_NAME"

echo "✅ Build succeeded → $APP_BUNDLE"
echo ""
echo "▶  Launching..."
open "$APP_BUNDLE"
