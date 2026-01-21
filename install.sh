#!/bin/bash
set -e

echo "Building AIReader (Release)..."
swift build -c release

echo "Updating AIReader.app..."
# Ensure basic structure
mkdir -p AIReader.app/Contents/MacOS
mkdir -p AIReader.app/Contents/Resources

# Copy binary
cp .build/release/AIReader AIReader.app/Contents/MacOS/

# Copy Info.plist
cp Info.plist AIReader.app/Contents/Info.plist

# Sign with entitlements
echo "Signing..."
# Note: Entitlements path must be absolute or relative to CWD
codesign --force --deep --sign - --entitlements AIReader.entitlements AIReader.app

# Install to /Applications
echo "Installing to /Applications..."
rm -rf /Applications/AIReader.app
cp -r AIReader.app /Applications/

echo "Success! AIReader.app has been installed to /Applications."
echo "You can launch it via Spotlight or Finder."
