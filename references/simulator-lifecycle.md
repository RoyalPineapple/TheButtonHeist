# Simulator Lifecycle Management

Command reference for creating, deploying to, and cleaning up iOS Simulators via `xcrun simctl`. Use these commands to set up a test environment before fuzzing.

All commands require Xcode to be installed. Run `xcode-select -p` to verify.

## Discovery

### List available device types and runtimes

```bash
# Device types (iPhone 16 Pro, iPad Air, etc.)
xcrun simctl list devicetypes

# Installed runtimes (iOS 18.0, iOS 17.5, etc.)
xcrun simctl list runtimes

# All existing simulators with their UDIDs and states
xcrun simctl list devices available

# JSON output for scripting
xcrun simctl list devices available --json
```

### Find a specific runtime ID

```bash
# Example: find the iOS 18 runtime
xcrun simctl list runtimes | grep "iOS 18"
# Output: iOS 18.0 (18.0 - 22A3354) - com.apple.CoreSimulator.SimRuntime.iOS-18-0
```

### Find a specific device type ID

```bash
# Example: find iPhone 16 Pro
xcrun simctl list devicetypes | grep "iPhone 16 Pro"
# Output: iPhone 16 Pro (com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro)
```

## Creating Simulators

### Create a new simulator

```bash
xcrun simctl create <name> <device-type-id> <runtime-id>
# Returns: the new simulator's UDID

# Example:
xcrun simctl create "FuzzTarget" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-18-0
```

### Clone an existing simulator

Cloning copies all installed apps, settings, and state. Faster than creating fresh + reinstalling.

```bash
xcrun simctl clone <source-UDID> <new-name>
# Returns: the clone's UDID
```

## Booting

### Boot a simulator

```bash
xcrun simctl boot <UDID>
```

Boot is asynchronous — the simulator may still be loading after the command returns. Use `bootstatus` to wait:

```bash
xcrun simctl bootstatus <UDID>
# Blocks until the simulator is fully booted
```

### Boot without Simulator.app window (headless)

Just don't open Simulator.app. The `boot` command starts the simulator service without a GUI. All functionality works headless — app launching, screenshots, accessibility tree, etc.

```bash
# Boot headless (just don't open Simulator.app)
xcrun simctl boot <UDID>
xcrun simctl bootstatus <UDID>

# If you DO want the window later:
open -a Simulator --args -CurrentDeviceUDID <UDID>
```

## App Deployment

### Build the app (once)

The app only needs to be built once. The `.app` bundle can be installed on multiple simulators.

```bash
# Build for simulator (from the repo root)
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=<UDID>" build

# Find the built .app bundle
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)
```

### Install and launch

```bash
# Install
xcrun simctl install <UDID> "$APP"

# Launch
xcrun simctl launch <UDID> com.buttonheist.testapp

# Launch and stream stdout/stderr
xcrun simctl launch --console <UDID> com.buttonheist.testapp
```

### Known issue: resource bundle crash

If the app crashes at launch with a `Bundle.module` assertion:

```bash
INSTALLED=$(xcrun simctl get_app_container <UDID> com.buttonheist.testapp)
BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "AccessibilitySnapshot_AccessibilitySnapshotParser.bundle" -path "*/Debug-iphonesimulator/*" | head -1)
cp -R "$BUNDLE" "$INSTALLED/Frameworks/"
xcrun simctl launch <UDID> com.buttonheist.testapp
```

### Verify InsideMan is advertising

```bash
# Look for Bonjour service
timeout 5 dns-sd -B _buttonheist._tcp .
# Should show an "Add" entry with the app name
```

## App Management

### Terminate a running app

```bash
xcrun simctl terminate <UDID> com.buttonheist.testapp
```

### Uninstall an app

```bash
xcrun simctl uninstall <UDID> com.buttonheist.testapp
```

### Relaunch (terminate + launch)

```bash
xcrun simctl terminate <UDID> com.buttonheist.testapp
xcrun simctl launch <UDID> com.buttonheist.testapp
```

### Get app container paths

```bash
# App bundle location
xcrun simctl get_app_container <UDID> com.buttonheist.testapp

# App data directory
xcrun simctl get_app_container <UDID> com.buttonheist.testapp data

# App group containers
xcrun simctl get_app_container <UDID> com.buttonheist.testapp groups
```

## Simulator State

### Erase all content and settings (keep simulator)

```bash
xcrun simctl erase <UDID>
```

### Screenshots and video

```bash
# Screenshot
xcrun simctl io <UDID> screenshot /tmp/screen.png

# Record video (Ctrl+C to stop)
xcrun simctl io <UDID> recordVideo /tmp/recording.mp4
```

### Open a URL

```bash
xcrun simctl openurl <UDID> "https://example.com"
xcrun simctl openurl <UDID> "myapp://deeplink/path"
```

### Push notifications

```bash
# From a JSON payload file
xcrun simctl push <UDID> com.buttonheist.testapp notification.json
```

### Logs

```bash
# Stream all logs
xcrun simctl spawn <UDID> log stream

# Filter to specific app
xcrun simctl spawn <UDID> log stream --predicate 'processImagePath endswith "AccessibilityTestApp"'
```

## Cleanup

### Shutdown a simulator

```bash
xcrun simctl shutdown <UDID>

# Shutdown all booted simulators
xcrun simctl shutdown all
```

### Delete a simulator

```bash
xcrun simctl delete <UDID>
```

### Delete all unavailable simulators

Removes simulators whose runtime is no longer installed:

```bash
xcrun simctl delete unavailable
```

## Complete Setup Flow

End-to-end example: create a simulator, deploy the app, and verify it's reachable.

```bash
# 1. Find the latest runtime and device type
RUNTIME=$(xcrun simctl list runtimes --json | python3 -c "
import json,sys
rts = json.load(sys.stdin)['runtimes']
ios = [r for r in rts if r['isAvailable'] and 'iOS' in r['name']]
print(ios[-1]['identifier'])" 2>/dev/null)

DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"

# 2. Create and boot
SIM_UDID=$(xcrun simctl create "FuzzTarget" "$DEVICE_TYPE" "$RUNTIME")
echo "Created simulator: $SIM_UDID"
xcrun simctl boot "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID"

# 3. Build the app (skip if already built)
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build 2>&1 | tail -1

# 4. Install and launch
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp

# 5. Verify
echo "Waiting for Bonjour advertisement..."
timeout 5 dns-sd -B _buttonheist._tcp . 2>&1 | head -5

echo "Simulator UDID: $SIM_UDID"
echo "Set BUTTONHEIST_DEVICE=$SIM_UDID in .mcp.json to target this simulator"
```

## Cleanup Flow

```bash
# Terminate the app
xcrun simctl terminate "$SIM_UDID" com.buttonheist.testapp

# Shutdown and delete
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

## Resource Limits

| Hardware | Comfortable Limit | Notes |
|----------|------------------|-------|
| M-series MacBook (16GB) | 5 simulators | ~1.3GB RAM each |
| M-series Mac Mini (16GB) | 10 simulators | May need system tuning |
| M-series (32GB+) | 10-12 simulators | Comfortable headroom |

Each simulator uses ~150 processes and ~3,000 file descriptors. Default macOS limits support about 9-10 simultaneous simulators. For more, system limits need to be raised via LaunchDaemons (see `thoughts/shared/research/2026-02-17-parallel-simulator-fuzzing.md`).
