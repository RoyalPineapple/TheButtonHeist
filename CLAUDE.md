# CLAUDE.md

## README.md is protected

The README is the face of this project. Its tone, prose, structure, and argumentative arc were carefully crafted and are not up for rewrite. **Do not restructure, rephrase, or rewrite README.md.** You may:

- Fix factual errors (stale counts, wrong tool names, broken links)
- Fix grammar or typos
- Add a new section if a feature ships that has no README coverage

You may **not**:

- Reorder sections or change the narrative flow
- Rewrite prose to "improve" clarity or tone
- Remove content unless the underlying feature was deleted
- Summarize, condense, or expand existing sections

If you believe the README needs substantive changes, say so and explain why — don't make the edit.

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

Re-run the canonical generate script after changing any `Project.swift`, `Workspace.swift`, or `Tuist/Package.swift`:

```bash
./scripts/generate-project.sh
```

The script wraps `tuist install && tuist generate --no-open` and then runs `scripts/clean-pbxproj.py` over every generated `project.pbxproj` to strip known dirty patterns: hardcoded `SRCROOT = /Users/...`, duplicate `$(inherited)` entries, and duplicate header / framework / runpath search path entries. The pre-commit hook runs the same cleaner so anything that slips through gets surfaced before a commit lands.

Calling `tuist generate` directly still works for quick iteration, but prefer the wrapper before committing — otherwise you risk pushing the noise above.

**Never edit `.xcodeproj` or `.xcworkspace` files directly.** Always modify the Tuist configuration (`Project.swift`, `Workspace.swift`, `Tuist/Package.swift`) and regenerate. After regenerating, commit the updated `.xcodeproj` and `.xcworkspace` files.

**Never commit hardcoded absolute paths in `.xcodeproj` files.** Xcode resolves `SRCROOT` automatically from the `.xcodeproj` location — never set it explicitly in build settings. Hardcoded paths like `SRCROOT = /Users/...` break builds for every other developer and CI. The cleaner strips these automatically; if you see one survive, investigate the Tuist configuration.

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

## No `accessibilityIdentifier` in Demo Screens

`accessibilityIdentifier` is an escape hatch, not a feature. It helps developers write UI tests, but it does nothing for accessibility users — VoiceOver never reads it, Switch Control never sees it, and it actively harms Button Heist's mission. The whole point is to navigate apps through the real accessibility user space: labels, values, traits, hints, and actions. If an element can only be found by identifier, that element is invisible to a real user and the heist should fail.

**Do not add `accessibilityIdentifier` to demo app screens** (`TestApp/Sources/`, `TestApp/UIKitSources/`). Instead, make every element findable by its natural accessibility properties — the same properties a VoiceOver user relies on. This is the bar: if the agent can't find it, a blind user can't either, and the fix is better accessibility, not an identifier.

Research screens (`TestApp/ResearchSources/`) are exempt — they probe the accessibility tree at the SPI level and use identifiers functionally to locate specific test fixtures.

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

### Test Framework

`TheScore` value-type tests and MCP sync tests use Swift Testing (`@Test` / `#expect`); everything else uses `XCTestCase`. Keep the split consistent — don't port across frameworks opportunistically.

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

## Explicit State Machines

Model multi-phase lifecycle as an enum with associated data — not as coordinated optionals and booleans at the class/struct level. The litmus test: if two or more fields co-vary to represent a single "phase", they belong inside an enum case's associated value, not as top-level properties.

**What to watch for:**
- Optional resources that must be non-nil only during certain phases (e.g. `writer: AVAssetWriter?` that exists only while recording).
- Task handles paired with a phase flag (`pollingTask: Task? + isPolling: Bool`).
- Booleans derived from other state (`didLogWarning` that tracks whether an array hit a cap).
- Parallel collections tracking the same entity through lifecycle stages (e.g. `pendingClients: Set<Int>` + `authenticatedClients: Set<Int>` — a client's phase should be a single enum value in one dictionary, not membership in multiple sets).
- Cleanup methods that nil out a dozen fields to return to "idle" — a sign the idle state carries no data but the type allows stale data to linger.

**Rules:**
- Each enum case carries exactly the data valid for that phase. Transitioning between cases is the only way to enter or leave a phase — no partial setup, no stale fields.
- If a phase needs mutable bookkeeping (frame counts, timestamps), put it in a struct and store the struct as the associated value.
- Prefer making impossible states unrepresentable over guarding against them at runtime. A `guard` that checks for an impossible combination is a sign the state model is too loose.
- When an existing type already has a state enum but stores phase-specific data as sibling optionals, refactor the data into associated values on the enum cases.

**Example — before (implicit):**
```swift
var state: State = .idle
var writer: AVAssetWriter?      // non-nil only during .recording/.finalizing
var captureTimer: Task?          // non-nil only during .recording
var startTime: Date?             // non-nil only during .recording/.finalizing
```

**After (explicit):**
```swift
enum State {
    case idle
    case recording(RecordingSession)
    case finalizing(FinalizingSession)
}
```

Where `RecordingSession` and `FinalizingSession` are structs carrying exactly the fields valid for that phase. Canonical examples: `ConnectionPhase`, `ReconnectPolicy`, `RecordingPhase` in TheHandoff.

## Functional Over Imperative

Swift has first-class support for a functional style — value types, enums with associated data, `map`/`compactMap`/`reduce`, `lazy` sequences, result builders, and strong generics. Use them. The goal is code where correctness is structural: if it compiles and the types line up, it's hard to get wrong.

**Use the language:**

- **`map`/`compactMap`/`filter`/`reduce` over `for` loops with mutable accumulators.** A `for` loop that appends to a `var array` is an imperative encoding of a transform. Use the functional version — it's shorter, the compiler can reason about it, and there's no intermediate mutable state to get wrong. Reserve `for` loops for side-effectful iteration (UI updates, network calls).
- **`lazy` sequences for multi-step pipelines.** When chaining `filter`/`map`/`compactMap`, use `lazy` to avoid allocating intermediate arrays. This is especially relevant for element pipelines where we filter thousands of accessibility elements.
- **Enums with associated data as result types.** Instead of returning a tuple of optionals or a struct with fields that are only valid in certain states, return an enum where each case carries exactly its data. `Result<T, E>` is the simplest case; domain-specific enums (like `ResolutionResult`) are better when there are more than two outcomes.
- **`folded()` / recursive enum traversal over switch-and-recurse.** When walking a recursive enum like `AccessibilityHierarchy`, define a `folded(onElement:onContainer:)` method that does the recursion once. Callers supply closures for each case. This eliminates the repeated `switch` + manual recursion pattern.
- **Struct tokens over parameter sprawl.** When a function needs to capture a snapshot of state (for before/after comparison, deferred processing, etc.), bundle it into a struct. The struct is the proof that state was captured; its type prevents mixing up arguments. Canonical example: `captureBeforeState()` returns a `BeforeState` struct consumed by `actionResultWithDelta(before:)`, replacing four loose parameters.
- **Computed properties over synchronized state.** If a value can be derived from other state, make it a computed property. A cache is acceptable when profiling justifies it — but key the cache on source data (fingerprints, hashes), not imperative "dirty" flags.

**Design principles:**

- **One codepath, not two.** When success and failure need different data in the result, make that difference a parameter (a flag, an optional error kind), not a structural fork. Two codepaths assembling the same result type will inevitably drift.
- **Separate pure reads from side effects.** If a function both queries state and mutates it, split it. Pure reads are testable without setup, composable without ordering constraints, and safe to call speculatively.
- **Declarative predicates over imperative decisions.** Express skip/include/transform decisions as value comparisons (fingerprint equality, set membership), not as stateful flags set at an earlier point. The decision should be auditable from the values alone.

**What to watch for:**
- A `for` loop building a result array that could be a single `map`/`compactMap`/`reduce` expression.
- Two branches assembling the same return type with overlapping but slightly different logic.
- Functions that take more than 3-4 parameters of "context" that are really a snapshot of state at a point in time — bundle them into a struct.
- A `var didX: Bool` that exists only to prevent doing X twice — derive the need from whether X's precondition still holds.
- Ad-hoc recovery code that patches up inconsistencies created by an earlier imperative step. If you need recovery, the pipeline has a structural gap — fix the pipeline.

## Currency Types: Elements and Targets

Two type families are the currency for referring to UI elements. Use them everywhere — never invent new types to represent a subset of their data.

**Canonical element types** (from AccessibilitySnapshotParser):
- `AccessibilityElement` — a leaf element with label, identifier, value, traits, frame, activation point, and custom actions. This is the parsed representation of a live UIKit accessibility element.
- `AccessibilityHierarchy` — the tree: `.element(AccessibilityElement, traversalIndex)` or `.container(AccessibilityContainer, children)`. TheStash holds the latest version inside the current `Screen` value after each accessibility refresh.

**Screen value** (TheInsideJob):
- `Screen` — immutable snapshot of one screen state. Bundles `elements: [String: ScreenElement]` (heistId → entry), `hierarchy`, `containerStableIds`, `heistIdByElement`, `firstResponderHeistId`, and `scrollableContainerViews`. Pure value semantics — TheStash holds exactly one mutable field of this type (`currentScreen`) and rebinds it on every parse. Exploration uses a local `var union: Screen` that's `merging(_:)`'d across page parses and committed back to `stash.currentScreen` at the end of the cycle. **Conflict rule**: `Screen.merging` is pure last-read-wins — `other`'s entry replaces `self`'s on heistId conflict; no field-level preservation. `name`/`id`/`heistIds` are derived on demand so they cannot drift from `hierarchy`.

**Target types** (TheScore wire types):
- `ElementTarget` — how callers refer to an element: `.heistId(String)` for stable ID lookup, `.matcher(ElementMatcher)` for predicate-based search. This is the currency type passed through TheFence, TheSafecracker, MCP, and CLI. Only TheStash resolves it to a live element.
- `ElementMatcher` — the predicate struct: label, identifier, value, traits, excludeTraits. String fields use case-insensitive equality with typography folding (smart quotes/dashes/ellipsis fold to ASCII; emoji/accents/CJK pass through). Traits use exact bitmask comparison. Matching is **exact or miss** — on a miss the resolver returns structured suggestions through the diagnostic path; there is no substring fallback. The same semantics are evaluated by `HeistElement.matches` on the client (TheScore) and `AccessibilityElement.matches` on the server (TheInsideJob), via the shared `ElementMatcher.stringEquals` helper.
- `HeistElement` — the wire representation sent to clients via `get_interface`. Contains heistId, label, value, traits, actions, frame, etc. Built by TheStash from `AccessibilityElement` + heistId assignment. This is a progressive-disclosure view for external consumers.

**Rules:**
- Pass `AccessibilityElement` and `AccessibilityHierarchy` internally when working with parsed accessibility data.
- Pass `Screen` when working with a committed snapshot of the resolution layer.
- Pass `ElementTarget` when referring to an element abstractly (all layers above TheStash).
- Do not create wrapper structs, snapshot types, or intermediate representations to hold subsets of these types. If you need a subset, pass the original and read what you need.
- Wire types (`HeistElement`, `ElementMatcher`, `ElementTarget`) live in TheScore and cross the Codable boundary. Internal types (`AccessibilityElement`, `AccessibilityHierarchy`, `Screen`) stay inside TheInsideJob.

**Strict off-screen rule**: `resolveTarget(.heistId(_:))` looks only in `currentScreen.elements`. If an heistId scrolled out of the viewport since the last commit, resolution returns `.notFound` with a near-miss suggestion — there is no fallback to a recorded position from a previous parse. Agents that want to act on an off-screen element must explicitly scroll first or refetch the interface.

## heistId synthesis is wire-format-stable

`synthesizeBaseId(_:)` in `TheStash.IdAssignment` produces deterministic heistIds derived from element content. **Synthesis is wire format.** Modifications are equivalent to changes to the JSON schema — they break recorded heists and the agent's predict-the-heistId pattern that benchmarks rely on. Treat any change to the synthesis rule like a wire-protocol bump.

The contract is locked by `SynthesisDeterminismTests` (property test across 200+ random permutations, plus a regression table of known input → known output). If you find yourself wanting to "improve" the heistId format, run `tuist test TheInsideJobTests` first — that test exists to make the contract auditable. Any change requires updating the regression table in the same PR.

## Versioning and Releases

There is one version: `buttonHeistVersion` in `ButtonHeist/Sources/TheScore/Messages.swift`. It is [CalVer](https://calver.org/) (`YYYY.MM.DD`, with same-day patches as `.N`), and CLI, MCP, and the iOS server all read it via TheScore. There is no separate "wire protocol version" — the handshake compares the server's and the client's `buttonHeistVersion` for exact equality and rejects on any mismatch. Inside (iOS server) and outside (CLI/MCP) must always be the same release; wire-format changes do not get their own version bump.

`buttonHeistVersion` is bumped only by `scripts/release.sh`. Commits between releases are not releases — the version constant stays put. Treat any temptation to bump the version mid-feature as a sign you're working around the release flow rather than with it. The script runs the full pipeline from a clean `main`: validate → bump → build all targets → run all tests → commit/tag/push. Pushing the tag triggers `.github/workflows/release.yml`, which builds the universal binaries, creates the GitHub release, and updates the Homebrew tap.

```bash
./scripts/release.sh              # Uses today's date
./scripts/release.sh 2026.04.03   # Explicit date
./scripts/release.sh --dry-run    # Preview only
```

## Callback Isolation Discipline

Public callback typealiases must declare their isolation in the closure type, not in a docstring. The compiler should enforce the isolation contract; documentation drifts.

```swift
// Good
public var onConnected: (@ButtonHeistActor (ServerInfo) -> Void)?

// Bad — isolation lives in a comment
/// Fires on @ButtonHeistActor.
public var onConnected: ((ServerInfo) -> Void)?
```

If a callback fires on a non-actor thread (network queue, ObjC runtime), still annotate explicitly: `@Sendable` for non-isolated, or document with the actor specified.

The custom SwiftLint rule `agent_unannotated_callback` flags `var on*: ((...) -> Void)?` patterns (public or internal) that are missing an isolation attribute.

## Sendable Value Types Without Actor Isolation

Sendable structs and enums must not carry `@MainActor` or `@ButtonHeistActor`. Actor isolation forces every consumer (tests, formatters, off-actor reads) into the actor for fields they're allowed to read concurrently. The `Sendable` conformance is sufficient.

If the type holds a non-Sendable field (e.g. `FileHandle`, a UIKit reference), use `@unchecked Sendable` with an inline comment justifying the serialization invariant — and explain *why* the actor isolation is enforced by the owner, not by the type itself. SwiftLint's `agent_unchecked_sendable_no_comment` rule blocks unjustified `@unchecked Sendable` at PR time.

Actor types (`actor Foo`) are different — those carry isolation by definition. Caseless namespace enums (`enum Foo { static func ... }`) that touch UIKit / scene state are also fine — `@MainActor` on them matches caller isolation, no instances are constructed. Annotate with `// swiftlint:disable:this agent_main_actor_value_type` and a short rationale.

## Task Lifetime Tracking

Every `Task { ... }` whose handle would otherwise be dropped must be stored at a known lifecycle point and cancelled on teardown. The handle being unobservable is the smell — fire-and-forget tasks contend for shared state and survive past the type that spawned them.

SwiftUI:

```swift
@State private var pendingTask: Task<Void, Never>?

// ...
.onAppear { pendingTask?.cancel(); pendingTask = Task { ... } }
.onDisappear { pendingTask?.cancel() }
```

Actors / `@MainActor` types:

```swift
private var pendingTasks: Set<Task<Void, Never>> = []

private func schedule() {
    let task = Task { /* work */ }
    pendingTasks.insert(task)
    // Tasks are cancelled in tearDown; if you need a task to remove itself
    // from the set on completion, factor that into a helper rather than
    // reaching for an IUO inside the closure.
}

func tearDown() {
    for task in pendingTasks { task.cancel() }
    pendingTasks.removeAll()
}
```

The single-line `Task { @MainActor in self.callback(...) }` bridge is its own anti-pattern — the call site has no handle, no cancellation, no ordering guarantee. SwiftLint's `agent_callback_bridge_task` rule flags it; annotate the callback's isolation in its closure type and call it directly.

## One Error Type Per Logical Domain

Don't introduce a new `enum FooError: Error` without first asking whether an existing error type covers the case. The codebase has authoritative error types per layer:

- `TheScore.ServerError` — wire-level errors broadcast from server to client
- `TheHandoff.ConnectionError` — connection lifecycle; also the associated value of `ConnectionPhase.failed` (the type is `Equatable` so the phase compares structurally)
- `FenceError` — CLI/MCP-facing dispatch errors
- `BookKeeperError` — session lifecycle errors

Per-module private errors are acceptable but should be auditable. If a new domain genuinely needs a new error type, document its boundary and what the existing types couldn't carry.

## CLI-First Development

- **The CLI is the canonical test client.** All features must be usable from the command line.
- This enables a full feedback loop for agentic workflows where automated tools can exercise the entire feature set.
- When adding new functionality, ensure corresponding CLI commands or flags are available.

## CLI/MCP Sync Contract

- `buttonheist session` is a thin interface over `TheFence`; the MCP server exposes 23 purpose-built tools that each dispatch to `TheFence`.
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

## Benchmark and Validation Harness

The `bh-infra` repo (`.context/bh-infra/`, clone via `/setup-context bh-infra`) contains an agent-driven benchmark and validation harness. It launches Claude with the BH MCP server against the BH Demo app and scores results against expected values across 15 tasks.

### Quick validation after code changes

```bash
cd .context/bh-infra
./pool.sh --validate --workers 3
```

Runs all tasks, bh config, 1 trial each, 3 parallel workers. Exits 0 (pass) or 1 (fail). Use `--min-score 1.0` for strict mode (default 0.5 allows partial credit).

### Full benchmark

```bash
./pool.sh --workers 3 -c bh -n 3 --save-baseline bh-YYYYMMDD-description
```

### Reports and comparisons

```bash
./report.sh results/<run-id>/ --verdict                              # pass/fail gate
./report.sh results/<run-id>/ --baseline bh-20260402-state-machines  # vs stored baseline
./report.sh results/<new-run>/ --compare results/<old-run>/          # two runs
```

Save a new baseline when landing major changes.

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

## AccessibilitySnapshotBH Submodule

The `AccessibilitySnapshotBH` submodule points at our fork (`RoyalPineapple/AccessibilitySnapshotBH`) on `main`. Upstream is `cashapp/AccessibilitySnapshot` (default branch: `main`). Our `main` is rebased on upstream `main` and carries five targeted commits:

1. `elementVisitor` closure on the hierarchy parser + xcodegen project support
2. `Hashable` conformance on `AccessibilityElement`
3. `traitNames` computed property and `fromNames` static method on UIAccessibilityTraits
4. `containerVisitor` closure on the hierarchy parser + `.scrollable(contentSize:)` container type
5. Popover modal sibling fix: traverse from the last modal subview onward (`subviews[lastModalIndex...]`) so popover content presented as a sibling after an empty dismiss region is not dropped

**Rules for this submodule:**
- Only touch files in the hierarchy parser (`Sources/AccessibilitySnapshot/Parser/`).
- Keep changes minimal and targeted — do not modify snapshot testing, examples, or package config.
- When upstream `cashapp/AccessibilitySnapshot:main` updates, rebase our `main` onto the new upstream `main` rather than merging.
- After updating the submodule, run `git submodule update --remote` and commit the new pin.

## Swift File Structure

Every Swift file follows the same section order. Skip sections that don't apply, but never reorder them.

1. **Conditional compilation guards** (`#if canImport(UIKit)`, `#if DEBUG`)
2. **Imports** — system frameworks, then project modules, then third-party. One blank line between groups when there are three or more imports total.
3. **File-level declarations** — loggers, constants, free functions. Never at the bottom.
4. **Primary type declaration** with a DocC summary comment.
5. **Nested types** (`MARK: - Nested Types`) — enums, structs, typealiases. If >30 lines, move to its own file.
6. **Properties** (`MARK: - Properties`) — stored lets, stored vars, computed vars. Grouped by visibility. Properties always come before methods.
7. **Init** (`MARK: - Init`)
8. **Responsibility groups** — each logical responsibility gets its own `MARK: -` section. Name the MARK after what it does, not what it is (`MARK: - Refresh Pipeline`, not `MARK: - Methods`). Within each section: public first, then internal, then private.
9. **Private helpers** (`MARK: - Private Helpers`) — catch-all for small utilities that don't fit a responsibility group.
10. **Conditional compilation closing** (`#endif // DEBUG`, `#endif // canImport(UIKit)`)

Rules:
- No bare methods floating outside of a MARK section (except properties and init).
- Never interleave properties with methods.
- Extensions on the same type in the same file use MARK sections, not `extension` blocks — unless the extension is for a protocol conformance.
- Extension files (`TheBrains+Dispatch.swift`) have a single MARK at the top of the extension body describing their purpose.
- `#endif` comments always say what they close.

## DocC Documentation

DocC comments (`///`) go on the API surface — types, public/internal methods, and public/internal properties that aren't self-evident. Use a one-line summary. Add a longer description only when the behavior isn't obvious from the name and signature.

```swift
/// Resolve a target to a unique element.
///
/// Returns `.resolved` on success, `.notFound` or `.ambiguous` with
/// diagnostics on failure.
func resolveTarget(_ target: ElementTarget) -> TargetResolution {
```

Do NOT document:
- Private methods with self-evident names
- Properties where the type and name say it all
- Code flow that reads clearly
- Closing braces or section separators

Remove noise comments when encountered:
- Empty `// MARK: -` with no text
- `// TODO:` or `// FIXME:` with no actionable content
- Comments that restate the code
- Commented-out code

## Dossier Maintenance

Crew member dossiers live in `docs/dossiers/`. When a PR changes a crew member's responsibilities, adds/removes types, or changes architecture:
- Update the relevant dossier file
- Update `docs/dossiers/README.md` (the overview) if module dependencies change
- Keep diagrams current
