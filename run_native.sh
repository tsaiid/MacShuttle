#!/bin/bash
set -e

# Build the Swift project
echo "🔨 Building Native MacShuttle..."
swift build -c release

# Copy binary to root for easy access
cp .build/release/MacShuttle ./MacShuttleNative

# Ad-hoc sign the binary
codesign --force --deep --sign - ./MacShuttleNative

echo "✅ Build Complete."
echo "🚀 Launching MacShuttleNative..."
echo "⚠️  Note: You may need to grant 'Accessibility' permissions to this terminal or the app."

./MacShuttleNative