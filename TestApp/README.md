# Test Application

A sample iOS app that serves as the integration target for ButtonHeist. It exercises every gesture type, control variant, and accessibility pattern that TheInsideJob supports.

The app embeds TheInsideJob — it auto-starts when the app launches, no code changes needed.

## BH Demo

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
| **UIKit Form** | Text fields, UISwitch, UISegmentedControl, submit/cancel buttons |
| **UIKit Table View** | 3-section grouped table with disclosure indicators and selection |
| **UIKit Collection View** | 3-column grid of accessibility category items |
| **Research** | Accessibility SPI harness, trait probes, and diagnostic tools |

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

Controls should be findable through their natural accessibility labels, values,
traits, hints, and actions. Research harness screens may use identifiers when
they are testing accessibility tree mechanics directly.

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
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/BHDemo.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"
TASK_SLUG="accra-scroll-detection"  # use {workspace}-{task-slug}
INSIDEJOB_PORT=$((RANDOM % 10000 + 20000))
SIMCTL_CHILD_INSIDEJOB_PORT="$INSIDEJOB_PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TASK_SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$TASK_SLUG" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
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
