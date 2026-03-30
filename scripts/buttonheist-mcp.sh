#!/bin/bash
# Wrapper for buttonheist-mcp that derives the connection port from the built app's Info.plist.
# This avoids hardcoding the port — TestApp/Project.swift (InsideJobPort) is the single source of truth.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$BUTTONHEIST_DEVICE" ]; then
    APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/BH Demo.app 2>/dev/null | head -1)
    if [ -n "$APP" ]; then
        PORT=$(/usr/libexec/PlistBuddy -c "Print :InsideJobPort" "$APP/Info.plist" 2>/dev/null)
        if [ -n "$PORT" ] && [ "$PORT" -gt 0 ] 2>/dev/null; then
            export BUTTONHEIST_DEVICE="127.0.0.1:$PORT"
        fi
    fi
fi

exec "$REPO_ROOT/ButtonHeistMCP/.build/release/buttonheist-mcp" "$@"
