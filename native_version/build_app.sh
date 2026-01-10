#!/bin/bash
set -e

# Config
APP_NAME="MacShuttle"
APP_BUNDLE="${APP_NAME}.app"
# Since we are running this script inside native_version/, the build dir is relative to here
BUILD_DIR=".build/release"
BINARY_NAME="MacShuttle"

echo "🔨 Building Native MacShuttle..."
# We are already in the package root
swift build -c release

echo "📦 Packaging into ${APP_BUNDLE}..."

# Clean up old build
rm -rf "${APP_BUNDLE}"

# Create Directory Structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy Binary
cp "${BUILD_DIR}/${BINARY_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
cp Info.plist "${APP_BUNDLE}/Contents/"

# Copy Resources (Icons)
cp assets/icon-active-Template.png "${APP_BUNDLE}/Contents/Resources/"
cp assets/icon-inactive-Template.png "${APP_BUNDLE}/Contents/Resources/"
cp assets/icon-disconnected-Template.png "${APP_BUNDLE}/Contents/Resources/"
cp assets/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"

echo "🔏 Signing App Bundle..."
# Ad-hoc sign the bundle
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Build Complete."
echo "🚀 You can now move '${APP_BUNDLE}' to your /Applications folder."
echo "   Or run: open native_version/${APP_BUNDLE}"