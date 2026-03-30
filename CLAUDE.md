# CLAUDE.md

## Tuist Project Generation

This project uses [Tuist](https://tuist.io) to generate Xcode projects and workspaces. The generated `.xcodeproj` and `.xcworkspace` files are checked into git, so you don't need to run `tuist generate` after a fresh clone.

### Project structure

| File | Purpose |
|------|---------|
| `Workspace.swift` | Defines the `ButtonHeist` workspace (includes root project + `TestApp`) |
| `Project.swift` | Root project: TheScore, TheInsideJob, ButtonHeist frameworks + tests |
| `TestApp/Project.swift` | Demo apps: BH Demo (SwiftUI) and UIKitTestApp (UIKit) |
| `Tuist.swift` | Tuist configuration (default) |
| `Tuist/Package.swift` | External dependencies (ArgumentParser, AccessibilitySnapshotParser) |
| `Tuist/ProjectDescriptionHelpers/` | Reusable helpers for framework/app target templates |

### When to regenerate

Re-run `tuist generate` after changing any `Project.swift`, `Workspace.swift`, or `Tuist/Package.swift`:

```bash
# Install external dependencies (needed after changing Tuist/Package.swift)
tuist install

# Regenerate Xcode projects and workspace
tuist generate --no-open
```

**Never edit `.xcodeproj` or `.xcworkspace` files directly.** Always modify the Tuist configuration (`Project.swift`, `Workspace.swift`, `Tuist/Package.swift`) and regenerate. After regenerating, commit the updated `.xcodeproj` and `.xcworkspace` files.

**Never commit hardcoded absolute paths in `.xcodeproj` files.** Xcode resolves `SRCROOT` automatically from the `.xcodeproj` location — never set it explicitly in build settings. Hardcoded paths like `SRCROOT = /Users/...` break builds for every other developer and CI. If you see absolute paths in a generated `.pbxproj`, do not commit them — investigate and fix the Tuist configuration instead.

## Canonical Test Runner

Use `tuist test` as the canonical way to run tests in this repository.

- Do not use `swift test` for normal verification. SwiftPM does not model the hosted iOS test setup correctly and can produce misleading failures in this mixed macOS/iOS repo.
- Do not use raw `xcodebuild test` as the default workflow. Use it only when debugging Tuist or Xcode behavior.
- Do not use bare `tuist test` in this workspace. The default `ButtonHeist-Workspace` scheme mixes macOS and iOS targets and can pick an unintended destination.
- Always run `tuist test` with an explicit scheme. For iOS-hosted tests, also pass an explicit simulator device and OS.
- `tuist test` is selective by default. When you need the full suite, add `--no-selective-testing`.

Recommended commands:

```bash
tuist test TheScoreTests --no-selective-testing
tuist test ButtonHeistTests --no-selective-testing
tuist test TheInsideJobTests --platform ios --device "iPhone 16 Pro" --os 26.1 --no-selective-testing
```

If Tuist reports missing external dependencies, run:

```bash
tuist install
```

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

### App targets

Three apps in `TestApp/Project.swift`, all embedding TheInsideJob and TheScore:

| App | Bundle ID | Sources | Purpose |
|-----|-----------|---------|---------|
| **BH Demo** | `com.buttonheist.testapp` | `TestApp/Sources/` | SwiftUI demo screens for agents and benchmarking. Keep clean — no research or diagnostic UI. |
| **BH UIKit Demo** (UIKitTestApp) | `com.buttonheist.uikittestapp` | `TestApp/UIKitSources/` | UIKit variant of the demo app. |
| **BH Research** (ResearchApp) | `com.buttonheist.research` | `TestApp/ResearchSources/` | Accessibility SPI harness, trait probes, and diagnostic tools. Not for production use. |

All include a post-build script that copies the `AccessibilitySnapshotParser` resource bundle into the app (workaround for Tuist not handling this automatically).

When adding new screens:
- **Demo screens** (controls, scroll tests, standard UI patterns) go in `TestApp/Sources/` and are wired into `RootView.swift`
- **Research screens** (SPI experiments, trait probing, runtime inspection) go in `TestApp/ResearchSources/` and are wired into `ResearchApp.swift`

## Simulator Quick Start

Build and deploy the demo app to an iOS Simulator for end-to-end testing.

### Agent isolation model

Multiple agents run simultaneously, each with their own simulator. The full convention is documented in `.context/bh-infra/docs/MULTI_AGENT_SIMULATORS.md` (if available — clone via `/setup-context bh-infra`). The short version: **simulator name = token = instance ID = `{workspace}-{task-slug}`**.

Every agent must:

1. **Create a dedicated simulator** named `{workspace}-{task-slug}` (e.g. `accra-scroll-detection`)
2. **Launch the app with a unique port and a human-readable token** derived from the same slug
3. **Connect using that port and token** — mismatches are rejected, and the token tells you whose session you hit

The token is not just auth — it's a label. When an agent sees `accra-scroll-detection` in a connection error, it knows immediately whether that's its session or someone else's. Never use UUIDs or opaque strings as tokens.

### 1. Create a simulator for your task

Derive the simulator name and token from your workspace and task:

```bash
# Convention: {workspace}-{task-slug}
TASK_SLUG="accra-scroll-detection"

# Create a dedicated simulator
SIM_UDID=$(xcrun simctl create "$TASK_SLUG" "iPhone 16 Pro")
xcrun simctl boot "$SIM_UDID"
```

The same `TASK_SLUG` is used as the simulator name, the auth token, and the `INSIDEJOB_ID` — everything is self-documenting. Running `xcrun simctl list devices booted` becomes a dashboard of what every agent is doing.

### 2. Build the demo app

```bash
xcodebuild -workspace ButtonHeist.xcworkspace -scheme BH Demo \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Use the `BH Demo` scheme — this embeds TheInsideJob and all frameworks. Building just the `TheInsideJob` scheme only produces the framework without the app.

### 3. Install and launch

```bash
# Find the freshest build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/BH Demo.app | head -1)

# Pick a unique port; use the task slug as the token
INSIDEJOB_PORT=$((RANDOM % 10000 + 20000))

# Install and launch (bundle ID: com.buttonheist.testapp)
xcrun simctl install "$SIM_UDID" "$APP"
SIMCTL_CHILD_INSIDEJOB_PORT="$INSIDEJOB_PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TASK_SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$TASK_SLUG" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

Ports and tokens are dynamic — each agent must generate its own at launch time. Without env vars, the server picks an OS-assigned port and auto-generates a UUID token (visible in console logs). **Never use UUIDs or opaque strings as tokens** — use the human-readable task slug so agents can reason about session ownership.

### 4. Build the CLI and add to PATH

```bash
cd ButtonHeistCLI && swift build -c release && cd ..
export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
```

This uses the repo-relative path so it works in any workspace.

### 5. Verify

**If Bonjour works** (no firewall stealth mode):

```bash
timeout 5 dns-sd -B _buttonheist._tcp .
```

Should show an `Add` entry with the app name.

**If Bonjour is broken** (MDM stealth mode — see `docs/BONJOUR_TROUBLESHOOTING.md`):

```bash
BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT" BUTTONHEIST_TOKEN="$TASK_SLUG" buttonheist session
```

### 6. Teardown

When the task is complete, clean up the simulator:

```bash
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

## Pre-Commit Checklist

Before pushing any commit, verify the following:

### 1. Regenerate Xcode Projects
- **Always run `tuist generate` before pushing** to ensure the committed `.pbxproj` files match what Tuist produces. CI runs `tuist generate` and diffs — stale project files from local generates (duplicate build settings, hardcoded paths) will fail the check.
  ```bash
  tuist generate --no-open
  git add -- '*.pbxproj' '*.xcworkspacedata'
  ```

### 2. Build Verification
- **All targets must build successfully.** Run the full build:
  ```bash
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScore build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJob -destination 'generic/platform=iOS' build
  ```
- For device builds, include signing:
  ```bash
  xcodebuild -workspace ButtonHeist.xcworkspace -scheme BH Demo \
    -destination 'platform=iOS,name=Device' -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YOUR_TEAM_ID build
  ```

### 3. Tests Pass
- **All existing tests must pass.** Run the test suite:
  ```bash
  tuist test TheScoreTests --no-selective-testing
  tuist test ButtonHeistTests --no-selective-testing
  tuist test TheInsideJobTests --platform ios --device "iPhone 16 Pro" --os 26.1 --no-selective-testing
  ```
- If tests fail, fix the code or update tests to reflect intentional changes.

### 4. Documentation Up to Date
- **Documentation must reflect the current implementation.** Check these files:
  - `README.md` - Quick start, features, usage examples
  - `docs/API.md` - Public API documentation
  - `docs/ARCHITECTURE.md` - System design and component interaction
  - `docs/VERSIONING.md` - CalVer strategy and release workflow
  - `docs/WIRE-PROTOCOL.md` - Message format and protocol details
  - `docs/USB_DEVICE_CONNECTIVITY.md` - USB connection guide
- When changing behavior, ports, message formats, or configuration:
  - Update all affected documentation
  - Ensure code examples are correct and runnable
  - Verify Info.plist keys and default values are accurate

### 5. Test Coverage for New Systems
- **Major new features require tests.** When introducing:
  - New message types → Add protocol tests
  - New API methods → Add unit tests
  - New connection paths → Add integration tests
- Tests should be automatable (no manual verification required).

## Testing Philosophy

### One True Way

`tuist test` is the one true way to run tests in this repository.

- `TheScoreTests` and `ButtonHeistTests` run as explicit Tuist schemes.
- `TheInsideJobTests` must run as a hosted iOS test bundle via the `BH Demo` test host, so always use the `TheInsideJobTests` scheme with an explicit simulator destination.
- Use `--no-selective-testing` when you need to force the full suite instead of Tuist's default selective run.
- Treat `swift test` as a package-debugging tool, not as the source of truth for CI-style verification.

### Determinism First

All unit tests must be fully deterministic — no dependency on running apps, Bonjour discovery, network state, or wall-clock timing. Tests that touch real network or Keychain are **integration tests** and must be clearly labeled as such.

### Mocking Strategy

**Never let real Bonjour discovery or `NWConnection` run in a unit test.** These find live apps on the network, making tests flaky and environment-dependent.

The mock boundary is at the network layer: `DeviceConnecting` and `DeviceDiscovering` protocols. Real `TheFence` and `TheHandoff` are used in tests, but with mock closures injected (`makeDiscovery`, `makeConnection`) so no real network I/O occurs.

TheHandoff receives injectable closures (`makeDiscovery`, `makeConnection`) so tests can inject mock implementations. Default closures create the real `DeviceDiscovery` and `DeviceConnection`.

### What Belongs Where

| Test type | Can use | Must NOT use |
|-----------|---------|-------------|
| **Protocol tests** (TheScore) | Value types, Codable round-trips | Any networking or UIKit |
| **Handler/dispatch tests** (TheFence) | Real TheFence/TheHandoff with mock DeviceConnecting injected via TheHandoff factory, pure arg parsing | Real Bonjour, NWConnection |
| **Connection logic tests** (DeviceConnection) | Message injection, forced isConnected | Real NWListener, real TCP sockets |
| **Auth/session tests** (TheMuscle) | Callback injection | Real networking, real UI alerts |
| **Integration tests** (TLS, Keychain) | Real NWListener on loopback, real Keychain | Must be clearly labeled, must clean up after themselves |

### Naming Conventions

- Unit test files: `{Type}Tests.swift` (e.g., `TheFenceHandlerTests.swift`)
- Integration test files: `{Feature}IntegrationTests.swift` (e.g., `TLSIntegrationTests.swift`)
- Integration tests that require entitlements (Keychain, etc.) must note this in a file-level comment.

## Feature Development: API → Tests → Implementation

New features follow a strict three-phase workflow — define the contract, prove it with tests, then fill in the code.

### Phase 1: Define the API

Start by writing the public types, protocols, and method signatures. This is the contract — what the feature looks like from the outside. Stub out the bodies with `fatalError("not implemented")` or empty returns so it compiles but doesn't work yet.

- Define new enums, structs, and protocol requirements.
- Add method signatures to existing types (TheFence commands, TheHandoff callbacks, etc.).
- Wire up CLI commands and MCP tool definitions as thin shells.

### Phase 2: Write the tests

Write tests against the API you just defined. Every test should fail (red) because the implementations are stubs. This is eating your vegetables — it's the part you do first so the reward at the end is real.

- Unit tests for each new public method or message type.
- Handler/dispatch tests for new TheFence commands.
- Round-trip Codable tests for any new wire types in TheScore.
- Tests define the expected behavior; the implementation must satisfy them, not the other way around.

### Phase 3: Fill in the implementation

Now write the real code until every test goes green. When all tests pass, dessert is served — the feature is done and proven correct.

- Implement one test at a time if helpful; the test suite is your progress tracker.
- Do not skip back to Phase 1 to change the API just to make implementation easier — if the API needs to change, update the tests first.
- A feature is not complete until all tests from Phase 2 pass.

### Why this order matters

Writing tests before implementation keeps the design honest. If a test is hard to write, the API is probably wrong — and it's cheaper to fix the API before the implementation exists. By the time you're writing code in Phase 3, you have a clear target and an automated way to know when you've hit it.

## Git Branch Conventions

- **"main" means `origin/main`**. When instructions or conversation refer to `main`, always use `origin/main`. The local `main` branch may be stale.
- Before creating PRs, diffing, or merging, always `git fetch origin main` first.
- Periodically update local `main` to track `origin/main`: `git checkout main && git pull origin main`.

## Commit Hygiene

- **Always ensure code builds before committing.** Never commit code that doesn't compile or pass basic build checks.
- Run `xcodebuild` to verify the project builds successfully before staging changes.
- Keep commits atomic and focused on a single logical change.
- **Squash merge PRs into main.** When merging a PR to `main`, use squash merge with a single descriptive commit message that summarizes the entire change.

## Strict Build Policy

All targets build with **warnings as errors** (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`) and **strict concurrency** (`SWIFT_STRICT_CONCURRENCY = complete`). SwiftLint runs as a pre-commit hook (via `scripts/pre-commit`) and in CI as a dedicated job. All three must pass cleanly — no `// swiftlint:disable`, no `@preconcurrency import`, no `nonisolated(unsafe)` escape hatches, no `#warning` left behind.

The pre-commit hook is configured automatically when you run `mise install` (via the `postinstall` hook in `mise.toml`).

The goal is to use the features of the language — structured concurrency, Sendable checking, actor isolation — rather than silencing the compiler. If a warning surfaces, fix the design, don't suppress the diagnostic. If SwiftLint flags a pattern, refactor to satisfy the rule rather than disabling it inline.

When adding or changing code:
- Fix any new warnings introduced by your change before committing.
- Do not raise the SwiftLint `disabled_rules` list or add file-level disable comments.
- Do not weaken the concurrency strictness level for any target.
- If an upstream dependency produces warnings, isolate it behind a wrapper rather than lowering the project settings.

## Type Safety: Enums Over Raw Strings

Prefer typed enums (`enum Foo: String`) over raw strings for any value that has a known set of valid cases — command names, action types, status codes, option values, etc. Convert to and from strings only at system boundaries (CLI argument parsing, JSON deserialization, MCP tool dispatch). Internally, pass the enum everywhere.

- `TheFence.Command` is the canonical example: strings enter via `execute(request:)`, are parsed to the enum at the boundary, and flow as typed values through dispatch and handlers.
- `EditAction`, `SwipeDirection`, `ScrollDirection`, `ScrollEdge` follow the same pattern.
- When adding a new command, action type, or option set: define it as a `String`-backed enum with `CaseIterable` in the appropriate module, not as string literals scattered across switch statements.
- Use `.rawValue` only at serialization boundaries — never compare `.rawValue` against a string literal deeper in the stack.

## Currency Types: Elements and Targets

Two type families are the currency for referring to UI elements. Use them everywhere — never invent new types to represent a subset of their data.

**Canonical element types** (from AccessibilitySnapshotParser):
- `AccessibilityElement` — a leaf element with label, identifier, value, traits, frame, activation point, and custom actions. This is the parsed representation of a live UIKit accessibility element.
- `AccessibilityHierarchy` — the tree: `.element(AccessibilityElement, traversalIndex)` or `.container(AccessibilityContainer, children)`. TheBagman owns and caches these after each accessibility refresh.

**Target types** (TheScore wire types):
- `ElementTarget` — how callers refer to an element: `.heistId(String)` for stable ID lookup, `.matcher(ElementMatcher)` for predicate-based search. This is the currency type passed through TheFence, TheSafecracker, MCP, and CLI. Only TheBagman resolves it to a live element.
- `ElementMatcher` — the predicate struct: label, identifier, value, traits, excludeTraits. String fields use case-insensitive substring matching. Traits use exact bitmask comparison.
- `HeistElement` — the wire representation sent to clients via `get_interface`. Contains heistId, label, value, traits, actions, frame, etc. Built by TheBagman from `AccessibilityElement` + heistId assignment. This is a progressive-disclosure view for external consumers.

**Rules:**
- Pass `AccessibilityElement` and `AccessibilityHierarchy` internally when working with parsed accessibility data.
- Pass `ElementTarget` when referring to an element abstractly (all layers above TheBagman).
- Do not create wrapper structs, snapshot types, or intermediate representations to hold subsets of these types. If you need a subset, pass the original and read what you need.
- Wire types (`HeistElement`, `ElementMatcher`, `ElementTarget`) live in TheScore and cross the Codable boundary. Internal types (`AccessibilityElement`, `AccessibilityHierarchy`) stay inside TheInsideJob.

## Versioning and Releases

- **Product version**: [CalVer](https://calver.org/) `YYYY.MM.DD` (e.g. `2026.03.27`). Same-day patches append `.N` (e.g. `2026.03.27.1`). See `docs/VERSIONING.md`.
- **Protocol version**: SemVer, lives in `protocolVersion` in `Messages.swift`. Bump only when the wire format or handshake changes. The release script does not touch it.
- **Canonical product version** lives in `ButtonHeist/Sources/TheScore/Messages.swift` (`buttonHeistVersion`). CLI, MCP, and iOS server all read it via TheScore.
- **Releasing**: Use the release script — never bump version manually in multiple files:
  ```bash
  ./scripts/release.sh              # Uses today's date
  ./scripts/release.sh 2026.03.27   # Explicit date
  ./scripts/release.sh --dry-run    # Preview only
  ```
  The script updates all 6 version references. Then run the Pre-Commit Checklist (build + tests), commit, and tag: `git tag v2026.03.27`.

## CLI-First Development

- **The CLI is the canonical test client.** All features must be usable from the command line.
- This enables a full feedback loop for agentic workflows where automated tools can exercise the entire feature set.
- When adding new functionality, ensure corresponding CLI commands or flags are available.

## CLI/MCP Sync Contract

- `buttonheist session` is a thin interface over `TheFence`; the MCP server exposes 16 purpose-built tools that each dispatch to `TheFence`.
- The command source of truth is `TheFence.Command` enum in `ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift`.
- Any command add/remove/rename must update the `Command` enum in the same change.
- MCP tool definitions live in `ButtonHeistMCP/Sources/ToolDefinitions.swift`; keep them in sync with `Command.allCases`.
- For rapid MCP driving: prefer action `delta` responses and only call `get_interface` when context is stale.
- When handoff/session behavior changes, validate both builds in the same branch:
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

The `AccessibilitySnapshot` submodule points at our fork (`RoyalPineapple/AccessibilitySnapshot`) on the `buttonheist` branch. Upstream is `cashapp/AccessibilitySnapshot` (default branch: `main`). The `buttonheist` branch is rebased on upstream `main` and carries four targeted commits:

1. `elementVisitor` closure on the hierarchy parser + xcodegen project support
2. `Hashable` conformance on `AccessibilityElement`
3. `traitNames` computed property and `fromNames` static method on UIAccessibilityTraits
4. `containerVisitor` closure on the hierarchy parser + `.scrollable(contentSize:)` container type

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
