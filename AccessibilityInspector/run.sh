#!/bin/bash
set -e

cd "$(dirname "$0")"

# Kill any running instances
pkill -9 -f "AccessibilityInspector" 2>/dev/null || true
sleep 0.5

# Touch source files to force recompile
touch AccessibilityInspector/Views/ContentView.swift

# Build
echo "Building..."
swift build --target AccessibilityInspector 2>&1

# Find and run the binary
BINARY=".build/arm64-apple-macosx/debug/AccessibilityInspector"
if [ -f "$BINARY" ]; then
    echo "Launching..."
    exec "$BINARY"
else
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
