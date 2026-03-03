# Simulator Management

Command reference for iOS Simulator lifecycle and state snapshots via `xcrun simctl`.

## Discovery

```bash
xcrun simctl list devicetypes                   # Device types (iPhone 16 Pro, iPad Air, etc.)
xcrun simctl list runtimes                      # Installed runtimes (iOS 18.0, etc.)
xcrun simctl list devices available             # All simulators with UDIDs and states
xcrun simctl list devices available --json      # JSON output for scripting
```

## Creating Simulators

```bash
# Create new
xcrun simctl create <name> <device-type-id> <runtime-id>
# Returns: UDID

# Clone existing (copies apps, settings, state)
xcrun simctl clone <source-UDID> <new-name>
```

## Boot / Shutdown / Delete

```bash
xcrun simctl boot <UDID>                        # Boot (async)
xcrun simctl bootstatus <UDID>                  # Block until fully booted
xcrun simctl shutdown <UDID>                    # Shutdown one
xcrun simctl shutdown all                       # Shutdown all
xcrun simctl delete <UDID>                      # Delete one
xcrun simctl delete unavailable                 # Delete sims with uninstalled runtimes
```

Headless: just don't open Simulator.app. All functionality works without the GUI. To open the window later: `open -a Simulator --args -CurrentDeviceUDID <UDID>`

## App Deployment

```bash
# Build (once, from repo root)
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=<UDID>" build

# Find the built bundle
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)

# Install and launch
xcrun simctl install <UDID> "$APP"
xcrun simctl launch <UDID> com.buttonheist.testapp

# Launch with console output
xcrun simctl launch --console <UDID> com.buttonheist.testapp
```

**Resource bundle crash workaround**: If app crashes at launch with `Bundle.module` assertion:
```bash
INSTALLED=$(xcrun simctl get_app_container <UDID> com.buttonheist.testapp)
BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "AccessibilitySnapshot_AccessibilitySnapshotParser.bundle" -path "*/Debug-iphonesimulator/*" | head -1)
cp -R "$BUNDLE" "$INSTALLED/Frameworks/"
xcrun simctl launch <UDID> com.buttonheist.testapp
```

**Verify Bonjour**: `timeout 5 dns-sd -B _buttonheist._tcp .` — should show an "Add" entry.

## App Management

```bash
xcrun simctl terminate <UDID> com.buttonheist.testapp      # Terminate
xcrun simctl uninstall <UDID> com.buttonheist.testapp       # Uninstall
xcrun simctl get_app_container <UDID> com.buttonheist.testapp        # Bundle path
xcrun simctl get_app_container <UDID> com.buttonheist.testapp data   # Data directory
```

## Simulator Utilities

```bash
xcrun simctl erase <UDID>                                    # Erase all content/settings
xcrun simctl io <UDID> screenshot /tmp/screen.png            # Screenshot
xcrun simctl io <UDID> recordVideo /tmp/recording.mp4        # Record video (Ctrl+C to stop)
xcrun simctl openurl <UDID> "myapp://deeplink/path"          # Open URL
xcrun simctl push <UDID> com.buttonheist.testapp notif.json  # Push notification
xcrun simctl spawn <UDID> log stream --predicate 'processImagePath endswith "AccessibilityTestApp"'  # App logs
```

## Snapshots

Save and restore simulator state for time-machine-style testing.

```bash
xcrun simctl snapshot save <UDID> <name>        # Save
xcrun simctl snapshot restore <UDID> <name>     # Restore
xcrun simctl snapshot list <UDID>               # List
xcrun simctl snapshot delete <UDID> <name>      # Delete
```

**Naming**: `fuzz-<date>-<screen-name>` (e.g., `fuzz-20260217-settings-all-toggles-on`)

### When to Snapshot

- **Before exploring new screens**: Restore here instead of replaying from launch if the app crashes
- **Before destructive actions**: Extreme values, rapid-fire interactions, stress tests
- **At interesting states**: Specific configurations (all toggles on, form partially filled, deep navigation)

### Session Notes Integration

Track in `## Snapshots`:
```markdown
| Name | Screen | Description | Created At |
|------|--------|-------------|------------|
| fuzz-20260217-main-menu | Main Menu | Initial state | Action #0 |
```

### Crash Reproduction via Snapshot

1. Note the crash action and last snapshot before it
2. After relaunch: `xcrun simctl snapshot restore <UDID> <snapshot-name>`
3. Replay just the last few actions — minimal reproduction path

### Limitations

- Restoring kills and relaunches the app — wait for Bonjour re-advertisement
- Each snapshot can be hundreds of MB — clean up at session end
- Save/restore takes a few seconds

## Complete Setup Flow

```bash
RUNTIME=$(xcrun simctl list runtimes --json | python3 -c "
import json,sys
rts = json.load(sys.stdin)['runtimes']
ios = [r for r in rts if r['isAvailable'] and 'iOS' in r['name']]
print(ios[-1]['identifier'])" 2>/dev/null)
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
SIM_UDID=$(xcrun simctl create "FuzzTarget" "$DEVICE_TYPE" "$RUNTIME")
xcrun simctl boot "$SIM_UDID" && xcrun simctl bootstatus "$SIM_UDID"
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build 2>&1 | tail -1
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
timeout 5 dns-sd -B _buttonheist._tcp . 2>&1 | head -5
```

## Cleanup Flow

```bash
xcrun simctl terminate "$SIM_UDID" com.buttonheist.testapp
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

## Resource Limits

| Hardware | Comfortable Limit | Notes |
|----------|------------------|-------|
| M-series MacBook (16GB) | 5 simulators | ~1.3GB RAM each |
| M-series Mac Mini (16GB) | 10 simulators | May need system tuning |
| M-series (32GB+) | 10-12 simulators | Comfortable headroom |
