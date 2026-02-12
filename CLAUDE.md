# CLAUDE.md

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

- **Round-trip testing between the iOS app and CLI is essential.** The CLI drives the simulator, the app responds, and the CLI verifies the results.
- Use `xcrun simctl` and the project CLI to launch, interact with, and inspect the iOS app running in the simulator.
- Tests should be fully automatable: boot simulator → install app → run test scenarios via CLI → capture and verify output.
- This creates a complete feedback loop where an agent can make code changes, rebuild, deploy to simulator, and validate behavior without human intervention.
