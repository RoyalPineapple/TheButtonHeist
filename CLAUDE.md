# CLAUDE.md

## Simulator Quick Start

Build and deploy the test app to an iOS Simulator for end-to-end testing.

### 1. Pick a simulator

Always target simulators by UDID, never by name (names can collide across runtimes).

```bash
# List available simulators
xcrun simctl list devices available

# Pick one and store its UDID
SIM_UDID=<paste-udid-here>

# Boot it
xcrun simctl boot "$SIM_UDID"
```

### 2. Build the test app

```bash
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Use the `AccessibilityTestApp` scheme — this embeds InsideMan, Wheelman, and all frameworks. Building just the `InsideMan` scheme only produces the framework without the app.

### 3. Install and launch

```bash
# Find the freshest build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)

# Install and launch (bundle ID: com.buttonheist.testapp)
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

### 4. Known issue: resource bundle crash

Tuist doesn't copy `AccessibilitySnapshot_AccessibilitySnapshotParser.bundle` into the app. If the app crashes at launch with a `Bundle.module` assertion, copy the bundle manually:

```bash
INSTALLED=$(xcrun simctl get_app_container "$SIM_UDID" com.buttonheist.testapp)
BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "AccessibilitySnapshot_AccessibilitySnapshotParser.bundle" -path "*/Debug-iphonesimulator/*" | head -1)
cp -R "$BUNDLE" "$INSTALLED/Frameworks/"
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

### 5. Build the CLI and add to PATH

```bash
cd ButtonHeistCLI && swift build -c release && cd ..
export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
```

This uses the repo-relative path so it works in any workspace.

### 6. Verify

```bash
timeout 5 dns-sd -B _buttonheist._tcp .
```

Should show an `Add` entry with the app name. The CLI commands (`buttonheist watch --once`, `buttonheist action`, etc.) should now work.

### Tip: Skip Bonjour Discovery

For simulators, the InsideMan server always listens on `127.0.0.1:1455`. Set environment variables to skip the ~2s Bonjour discovery on every command:

```bash
export BUTTONHEIST_HOST=127.0.0.1
export BUTTONHEIST_PORT=1455
```

Or pass `--host` and `--port` flags directly:

```bash
buttonheist watch --once --host 127.0.0.1 --port 1455
```

**If direct connection fails:**
- Verify the app is running: `buttonheist list` (uses Bonjour, works without host/port)
- Both `BUTTONHEIST_HOST` and `BUTTONHEIST_PORT` must be set — if only one is set, it falls back to Bonjour
- After an app relaunch, wait 2-3 seconds for the server to start
- To reset: `unset BUTTONHEIST_HOST BUTTONHEIST_PORT`

## Pre-Commit Checklist

Before pushing any commit, verify the following:

### 1. Build Verification
- **All targets must build successfully.** Run the full build:
  ```bash
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build
  ```
- For device builds, include signing:
  ```bash
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
    -destination 'platform=iOS,name=Device' -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YOUR_TEAM_ID build
  ```

### 2. Tests Pass
- **All existing tests must pass.** Run the test suite:
  ```bash
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test
  ```
- If tests fail, fix the code or update tests to reflect intentional changes.

### 3. Documentation Up to Date
- **Documentation must reflect the current implementation.** Check these files:
  - `README.md` - Quick start, features, usage examples
  - `docs/API.md` - Public API documentation
  - `docs/ARCHITECTURE.md` - System design and component interaction
  - `docs/WIRE-PROTOCOL.md` - Message format and protocol details
  - `docs/USB_DEVICE_CONNECTIVITY.md` - USB connection guide
- When changing behavior, ports, message formats, or configuration:
  - Update all affected documentation
  - Ensure code examples are correct and runnable
  - Verify Info.plist keys and default values are accurate

### 4. Test Coverage for New Systems
- **Major new features require tests.** When introducing:
  - New message types → Add protocol tests
  - New API methods → Add unit tests
  - New connection paths → Add integration tests
- Tests should be automatable (no manual verification required).

## Commit Hygiene

- **Always ensure code builds before committing.** Never commit code that doesn't compile or pass basic build checks.
- Run `xcodebuild` to verify the project builds successfully before staging changes.
- Keep commits atomic and focused on a single logical change.

## CLI-First Development

- **The CLI is the canonical test client.** All features must be usable from the command line.
- This enables a full feedback loop for agentic workflows where automated tools can exercise the entire feature set.
- When adding new functionality, ensure corresponding CLI commands or flags are available.

## Feedback Loop Workflow

- **Development and diagnostics should be driven by feedback loops.** Make changes, then validate their output entirely via CLI and tools that an agent can use and verify.
- Avoid workflows that require manual GUI interaction for validation—if an agent can't verify it, automate it until it can.
- Build observability into features so their behavior can be inspected programmatically.

## End-to-End Testing with iOS Simulator

- Follow the **Simulator Quick Start** section above to build, install, and launch the test app.
- After making code changes, rebuild and reinstall using those same steps.
- Verify changes via CLI commands (`buttonheist watch --once`, `buttonheist action`, `buttonheist screenshot`, etc.) — not manual GUI inspection.
