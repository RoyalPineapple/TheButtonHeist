# CLAUDE.md

## Tuist Project Generation

This project uses [Tuist](https://tuist.io) to generate Xcode projects and workspaces. The generated `.xcodeproj` and `.xcworkspace` files are checked into git, so you don't need to run `tuist generate` after a fresh clone.

### Project structure

| File | Purpose |
|------|---------|
| `Workspace.swift` | Defines the `ButtonHeist` workspace (includes root project + `TestApp`) |
| `Project.swift` | Root project: TheScore, TheInsideJob, Wheelman, ButtonHeist frameworks + tests |
| `TestApp/Project.swift` | Demo apps: AccessibilityTestApp (SwiftUI) and UIKitTestApp (UIKit) |
| `Tuist.swift` | Tuist configuration (default) |
| `Tuist/Package.swift` | External dependencies (ArgumentParser, AccessibilitySnapshotParser) |
| `Tuist/ProjectDescriptionHelpers/` | Reusable helpers for framework/app target templates |

### When to regenerate

Re-run `tuist generate` after changing any `Project.swift`, `Workspace.swift`, or `Tuist/Package.swift`:

```bash
# Install external dependencies (needed after changing Tuist/Package.swift)
tuist install

# Regenerate Xcode projects and workspace
tuist generate
```

**Never edit `.xcodeproj` or `.xcworkspace` files directly.** Always modify the Tuist configuration (`Project.swift`, `Workspace.swift`, `Tuist/Package.swift`) and regenerate. After regenerating, commit the updated `.xcodeproj` and `.xcworkspace` files.

### Adding a dependency

1. Add the package to `Tuist/Package.swift`
2. Run `tuist install` to fetch it
3. Reference it in the relevant target with `.external(name: "PackageName")`
4. Run `tuist generate`

### Adding a new target

Use the helpers in `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`:
- `.framework(name:destinations:dependencies:)` for multi-platform frameworks (iOS 17.0 + macOS 14.0)
- `.app(name:destinations:deploymentTargets:sources:resources:dependencies:)` for apps

Or define targets directly in `Project.swift` / `TestApp/Project.swift`.

### Demo app details

The two test apps in `TestApp/Project.swift` both embed TheInsideJob and TheScore:

- **AccessibilityTestApp** (`com.buttonheist.testapp`) — SwiftUI, sources in `TestApp/Sources/`
- **UIKitTestApp** (`com.buttonheist.uikittestapp`) — UIKit, sources in `TestApp/UIKitSources/`

Both include a post-build script that copies the `AccessibilitySnapshotParser` resource bundle into the app (workaround for Tuist not handling this automatically).

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

Use the `AccessibilityTestApp` scheme — this embeds TheInsideJob, Wheelman, and all frameworks. Building just the `TheInsideJob` scheme only produces the framework without the app.

### 3. Install and launch

```bash
# Find the freshest build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)

# Install and launch (bundle ID: com.buttonheist.testapp)
xcrun simctl install "$SIM_UDID" "$APP"
APP_TOKEN=${APP_TOKEN:-INJECTED-TOKEN-12345}
SIMCTL_CHILD_INSIDEJOB_TOKEN="$APP_TOKEN" xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

### 4. Build the CLI and add to PATH

```bash
cd ButtonHeistCLI && swift build -c release && cd ..
export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
```

This uses the repo-relative path so it works in any workspace.

### 5. Verify

```bash
timeout 5 dns-sd -B _buttonheist._tcp .
```

Should show an `Add` entry with the app name. The CLI commands (`buttonheist session`, `buttonheist activate`, `buttonheist action`, etc.) should now work.

## Pre-Commit Checklist

Before pushing any commit, verify the following:

### 1. Build Verification
- **All targets must build successfully.** Run the full build:
  ```bash
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScore build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJob -destination 'generic/platform=iOS' build
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
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScoreTests test
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJobTests -destination 'platform=iOS Simulator,name=iPhone 16' test
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
- **Squash merge PRs into main.** When merging a PR to `main`, use squash merge with a single descriptive commit message that summarizes the entire change.

## CLI-First Development

- **The CLI is the canonical test client.** All features must be usable from the command line.
- This enables a full feedback loop for agentic workflows where automated tools can exercise the entire feature set.
- When adding new functionality, ensure corresponding CLI commands or flags are available.

## CLI/MCP Sync Contract

- `buttonheist session` is a thin interface over `TheFence`; the MCP server exposes 14 purpose-built tools that each dispatch to `TheFence`.
- The command source of truth is `ButtonHeist/Sources/ButtonHeist/CommandCatalog.swift`.
- Any command add/remove/rename must update `CommandCatalog` in the same change.
- MCP tool definitions live in `ButtonHeistMCP/Sources/ToolDefinitions.swift`; keep them in sync with `CommandCatalog.all`.
- For rapid MCP driving: prefer action `delta` responses and only call `get_interface` when context is stale.
- When mastermind/session behavior changes, validate both builds in the same branch:
  - `cd ButtonHeistCLI && swift build -c release`
  - `cd ButtonHeistMCP && swift build -c release`

## Feedback Loop Workflow

- **Development and diagnostics should be driven by feedback loops.** Make changes, then validate their output entirely via CLI and tools that an agent can use and verify.
- Avoid workflows that require manual GUI interaction for validation—if an agent can't verify it, automate it until it can.
- Build observability into features so their behavior can be inspected programmatically.

## End-to-End Testing with iOS Simulator

- Follow the **Simulator Quick Start** section above to build, install, and launch the test app.
- After making code changes, rebuild and reinstall using those same steps.
- Verify changes via CLI commands (`buttonheist session`, `buttonheist activate`, `buttonheist action`, `buttonheist screenshot`, etc.) — not manual GUI inspection.

## Recording and Demo Commands

Slash commands for capturing recordings and demos from the connected iOS app. All commands require the app to be running with TheInsideJob embedded.

| Command | Description |
|---------|-------------|
| `/record` | Start a background screen recording |
| `/stop-recording` | Stop an in-progress recording and save the file |
| `/screenshot` | Capture a screenshot and display it inline |
| `/demo [feature]` | Create a polished 3-act feature demo video |

Recordings are saved to `demos/` with timestamped filenames. Default settings: `--fps 8 --scale 0.5 --inactivity-timeout 60`.

## Product and framework naming

- **Product name**: **Button Heist** (colloquially "the button heist"). We are not renaming to TheButtonHeist, Interface Heist, or UI Heist.
- **Formally** (code, API, module): use **TheInsideJob** for the iOS server framework.
- **Colloquially** (prose, chat): "inside job" or "Inside Job" is fine for that framework; don't over-correct.

## AccessibilitySnapshot Submodule

The `AccessibilitySnapshot` submodule points at our fork (`RoyalPineapple/AccessibilitySnapshot`) on the `buttonheist` branch. Upstream is `cashapp/AccessibilitySnapshot` (default branch: `main`). The `buttonheist` branch is rebased on upstream `main` and carries only two targeted commits:

1. `elementVisitor` closure on the hierarchy parser + xcodegen project support
2. `Hashable` conformance on `AccessibilityElement`

**Rules for this submodule:**
- Only touch files in the hierarchy parser (`Sources/AccessibilitySnapshot/Parser/`).
- Keep changes minimal and targeted — do not modify snapshot testing, examples, or package config.
- When upstream `cashapp/AccessibilitySnapshot:main` updates, rebase `buttonheist` onto the new `main` rather than merging.
- After updating the submodule, run `git submodule update --remote` and commit the new pin.

## Dossier Maintenance

Crew member dossiers live in `docs/dossiers/`. When a PR changes a crew member's responsibilities, adds/removes types, or changes architecture:
- Update the relevant dossier file
- Update `00-OVERVIEW.md` if module dependencies change
- Keep diagrams current
