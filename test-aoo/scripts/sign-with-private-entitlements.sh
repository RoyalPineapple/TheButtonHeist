#!/bin/bash
#
# Sign iOS app with private accessibility entitlements
# For use with TrollStore or jailbroken devices
#
# Usage: ./sign-with-private-entitlements.sh path/to/YourApp.app
#

set -e

APP_PATH="$1"
ENTITLEMENTS_PATH="$(dirname "$0")/../test-aoo/PrivateAccessibilityEntitlements.plist"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 path/to/YourApp.app"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# Get the binary name (usually same as app name without .app)
APP_NAME=$(basename "$APP_PATH" .app)
BINARY_PATH="$APP_PATH/$APP_NAME"

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "=============================================="
echo "Signing with Private Accessibility Entitlements"
echo "=============================================="
echo ""
echo "App: $APP_PATH"
echo "Binary: $BINARY_PATH"
echo "Entitlements: $ENTITLEMENTS_PATH"
echo ""

# Check if ldid is available
if ! command -v ldid &> /dev/null; then
    echo "ldid not found. Installing via Homebrew..."
    brew install ldid
fi

# Show current entitlements (if any)
echo "Current entitlements:"
ldid -e "$BINARY_PATH" 2>/dev/null || echo "(none)"
echo ""

# Sign with new entitlements
echo "Signing with private entitlements..."
ldid -S"$ENTITLEMENTS_PATH" "$BINARY_PATH"

echo ""
echo "New entitlements:"
ldid -e "$BINARY_PATH"

echo ""
echo "=============================================="
echo "Done! Next steps:"
echo "=============================================="
echo ""
echo "For TrollStore (iOS 14.0 - 17.0):"
echo "  1. Zip the .app folder into an .ipa"
echo "  2. Transfer to device"
echo "  3. Install via TrollStore"
echo ""
echo "For Jailbroken devices:"
echo "  1. Ensure AppSync Unified is installed"
echo "  2. Transfer to device"
echo "  3. Install via Filza or: ideviceinstaller -i YourApp.ipa"
echo ""
echo "For iOS Simulator:"
echo "  The Simulator may work without special signing."
echo "  Just build and run from Xcode."
echo ""
