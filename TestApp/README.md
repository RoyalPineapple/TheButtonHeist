# Test Applications

Two sample iOS apps that serve as integration targets for ButtonHeist. They exercise every gesture type, control variant, and accessibility pattern that TheInsideJob supports.

Both apps embed TheInsideJob — it auto-starts when the app launches, no code changes needed.

## SwiftUI Test App — "A11y SwiftUI"

- **Bundle ID**: `com.buttonheist.testapp`
- **Scheme**: `BH Demo`

### Screens

| Screen | What It Tests |
|--------|---------------|
| **Controls Demo** | Hub linking to 7 sub-demos (see below) |
| **Todo List** | List manipulation, swipe-to-delete, filters, custom accessibility actions |
| **Notes** | Text input, keyboard interaction, CRUD operations |
| **Calculator** | Button grids, rapid tapping, chained operations |
| **Touch Canvas** | Multi-touch drawing — tests `draw_path` and `draw_bezier` gestures |
| **Settings** | Segmented pickers, toggles, text fields, dynamic type |

### Controls Demo Sub-screens

| Sub-screen | Controls |
|------------|----------|
| Text Input | TextField, email field, SecureField, TextEditor |
| Toggles & Pickers | Toggle, menu Picker, segmented Picker, DatePicker, ColorPicker |
| Buttons & Actions | 5 button styles, Menu, custom accessibility actions (Favorite, Share) |
| Adjustable Controls | Slider (0–100), Stepper (0–10), Gauge, ProgressView |
| Alerts & Sheets | Alert, ConfirmationDialog, Sheet |
| Disclosure & Grouping | DisclosureGroup, LabeledContent |
| Display | Image, Label, Link, header Text |

All controls use `buttonheist.*` accessibility identifiers for reliable targeting.

## UIKit Test App — "A11y UIKit"

- **Bundle ID**: `com.buttonheist.uikittestapp`
- **Scheme**: `UIKitTestApp`

### Screens

| Screen | What It Tests |
|--------|---------------|
| **Form** | Text fields, UISwitch, UISegmentedControl, submit/cancel buttons |
| **Table View** | 3-section grouped table with disclosure indicators and selection |
| **Collection View** | 3-column grid of accessibility category items |

## Building and Running

### Simulator

```bash
# Pick a simulator
xcrun simctl list devices available
SIM_UDID=<paste-udid>
xcrun simctl boot "$SIM_UDID"

# Build
xcodebuild -workspace ButtonHeist.xcworkspace \
  -scheme BH Demo \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build

# Install and launch
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/BH Demo.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"
APP_TOKEN=${APP_TOKEN:-INJECTED-TOKEN-12345}
SIMCTL_CHILD_INSIDEJOB_TOKEN="$APP_TOKEN" xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

### Known Issue: Resource Bundle

Tuist doesn't copy `AccessibilitySnapshot_AccessibilitySnapshotParser.bundle` into the app. If it crashes at launch with a `Bundle.module` assertion:

```bash
INSTALLED=$(xcrun simctl get_app_container "$SIM_UDID" com.buttonheist.testapp)
BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "AccessibilitySnapshot_AccessibilitySnapshotParser.bundle" -path "*/Debug-iphonesimulator/*" | head -1)
cp -R "$BUNDLE" "$INSTALLED/Frameworks/"
APP_TOKEN=${APP_TOKEN:-INJECTED-TOKEN-12345}
SIMCTL_CHILD_INSIDEJOB_TOKEN="$APP_TOKEN" xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

### Verify

```bash
timeout 5 dns-sd -B _buttonheist._tcp .
```

You should see an `Add` entry with the app name. ButtonHeist MCP tools and CLI commands will now work.

## See Also

- [Project Overview](../README.md) — Architecture and quick start
- [CLAUDE.md](../CLAUDE.md) — Full simulator setup with troubleshooting
- [CLI Reference](../ButtonHeistCLI/) — Test the app via command line
