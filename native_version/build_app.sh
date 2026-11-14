#!/bin/bash
set -e

# Config
APP_NAME="MacShuttle"
APP_BUNDLE="${APP_NAME}.app"
# Since we are running this script inside native_version/, the build dir is relative to here
BUILD_DIR=".build/release"
BINARY_NAME="MacShuttle"

# Determine version from exact Git tag or VERSION file
GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || true)
if [[ "${GIT_TAG}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
    APP_VERSION="${BASH_REMATCH[1]}"
elif [ -f VERSION ]; then
    APP_VERSION=$(tr -d '[:space:]' < VERSION)
else
    APP_VERSION="1.0.0"
fi
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

echo "🔨 Building Native MacShuttle v${APP_VERSION} (${BUILD_NUMBER})..."
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

# Copy Info.plist and inject version
cp Info.plist "${APP_BUNDLE}/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_BUNDLE}/Contents/Info.plist"

# Copy Resources (Icons)
cp assets/icon-active-Template.png "${APP_BUNDLE}/Contents/Resources/"
cp assets/icon-inactive-Template.png "${APP_BUNDLE}/Contents/Resources/"
cp assets/icon-disconnected-Template.png "${APP_BUNDLE}/Contents/Resources/"
cp assets/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"

echo "🔏 Signing App Bundle..."
# Ad-hoc sign the bundle
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "🧹 Resetting TCC Accessibility Permissions..."
# This helps avoid the manual "minus/remove" step in System Settings
tccutil reset Accessibility com.tsaiid.MacShuttle || true

echo "✅ Build Complete."
echo "🚀 You can now move '${APP_BUNDLE}' to your /Applications folder."
echo "   Or run: open native_version/${APP_BUNDLE}"