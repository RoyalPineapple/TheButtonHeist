# CI integration

Heists run in CI in two topologies. Pick by where the test logic should live:
inside the app's own test bundle, or in a runner script that drives the app
from outside.

Both topologies share the version rule: the embedded `TheInsideJob` build and
the `buttonheist` CLI/MCP build must be the same release. The wire handshake
compares versions for exact equality and rejects mismatches, so pin the CLI to
the release your app embeds rather than installing "latest" in CI.

## Result artifact contract

CI result capture uses the repository's existing wrapper, collector, and
manifest scripts. The contract is the script flow and the raw result files it
uploads, not a new evidence format:

- `scripts/run-with-heist-results.sh` wraps a test or replay command, sets
  `BUTTONHEIST_RESULTS_DIR` and `BUTTONHEIST_RESULTS_MODE`, preserves the
  wrapped command's exit status, and supports `--ios-sandbox` for
  simulator-hosted test processes that must write results inside their own
  container.
- `scripts/collect-ios-heist-results.sh` copies `*.json` and `*.json.gz`
  results from simulator `buttonheist-results` directories into the host
  artifact directory. It also writes `collection-diagnostics.txt`, and missing
  results are diagnostics rather than collection-script failures.
- `scripts/write-ci-heist-result-manifest.sh` writes `manifest.txt` and
  `result-files.txt` into the artifact directory so downloaded CI artifacts
  are readable without custom tooling.

Upload the whole result directory after the manifest step. Consumers should
look for `manifest.txt`, then inspect the raw `.json` or `.json.gz` results
listed in `result-files.txt`.

## Topology 1: app-hosted tests (recommended)

Heists embed directly in XCTest or Swift Testing through `ButtonHeistTesting`
and execute in-process. There is no server, port, or token: the test host runs
the heist runtime against its own accessibility tree. Any CI that can run your
iOS test bundle can run heists — no extra infrastructure.

```swift
import ButtonHeistTesting
import XCTest

@MainActor
final class CheckoutHeistTests: XCTestCase {
    func testCheckoutCompletes() async throws {
        try await runHeist("Checkout.pay") {
            Activate(.label("Pay"))
                .expect(.changed(.elements([.appeared(.label("Payment Complete"))])))
        }
    }
}
```

For app-hosted targets that share teardown machinery with synchronous test
suites, use `runHeistSync` (see
[Swift heist authoring](SWIFT-HEIST-AUTHORING.md)). Failures report through
`XCTFail` at the call site, so heist failures appear in your runner's normal
test results — no separate report plumbing.

To keep results as build artifacts, record them explicitly and upload the
directory:

```swift
runHeistSync("Checkout.pay", recordResult: .always, to: resultsURL) {
    Activate(.label("Pay"))
        .expect(.changed(.elements([.appeared(.label("Payment Complete"))])))
}
```

If no URL is supplied, results are written under the process temporary
directory at `buttonheist-results/`.

In this repository, use the canonical test runner. It applies the result
wrapper and owns the Xcode result-bundle and recorded-heist-result paths:

```bash
BUTTONHEIST_RESULTS_MODE=failures \
  scripts/test-runner.py run ButtonHeistTests --selection full
```

iOS simulator-hosted test bundles write inside the app/test process sandbox.
The runner selects an explicit simulator, applies the sandbox sentinel, and
collects results after each run and during failure cleanup:

```bash
BUTTONHEIST_RESULTS_MODE=failures \
  scripts/test-runner.py run TheInsideJobTests --selection full \
  --simulator-name "$TASK_SLUG"
```

Button Heist owns six explicit `BH Demo`-hosted schemes. Target membership is
the coverage contract; CI does not partition these suites with test selectors:

| Scheme | Coverage |
|--------|----------|
| `TheInsideJobTests` | Deterministic core runtime and protocol tests |
| `TheInsideJobIntegrationTests` | Real loopback, TLS, live-window, gesture, and settle integration tests |
| `DogfoodFeatureFlowTests` | One semantic list mutation through the public heist API |
| `DogfoodRuntimeContractTests` | Public roots/prebuilt plans and advanced control flow |
| `AdversarialMutationTests` | Async reveal and stale-live-object recovery |
| `AdversarialNavigationTests` | Modal fail-closed behavior and nested scrolling |

`HostedBehaviorTests` combines the four dogfood and adversarial schemes. Those
targets contain seven focused live canaries, all of which run serially on pull
requests in one dedicated simulator. The scheduled adversarial workflow
owns the complete external-driver scenario matrix, with a short daily pass and
a deeper Sunday soak.

CI budgets macOS capacity explicitly:

- Portable release, parser, workflow, timing-parser, and automation contracts
  run on Linux.
- Pull requests use exactly three macOS runners: consolidated macOS validation
  (including every portable framework test target),
  deterministic iOS core plus a trimmed demo smoke using one shared build, and
  hosted behavior canaries.
- Pushes to `main` run those same three mandatory lanes. The genuine
  `TheInsideJobIntegrationTests` suite then runs behind the completed iOS core
  lane, keeping macOS concurrency at three.
- A final `exact-sha-suite` job records the commit, workflow revision, run ID,
  and every required suite conclusion in `buttonheist-exact-sha-suite`. Release
  admission accepts only that successful aggregate and validates its manifest.
- Successful jobs publish timing summaries. Recorded heist results and Xcode
  result bundles are retained only when a job fails; the release admission
  manifest is retained for every main run.

This keeps the main validation topology within the same three-runner ceiling
while making the exact release SHA prove the complete required suite. CI and
local validation both delegate test driving to `scripts/test-runner.py`.

Run the complete portable framework suite with:

```bash
scripts/test-runner.py run MacFrameworkTests --selection full
```

For a bounded, maintained projection of a contract or critical invariant, use a
named focus instead of reconstructing scheme and test selectors:

```bash
scripts/test-runner.py catalog
scripts/test-runner.py run --focus contract-results --selection full
```

Every invocation writes `run.json` beside its result artifacts. The record
includes the exact commit, whether the tracked source tree was clean, the
selected tests, phase, outcome, exit code, timeout state, duration, and executed
test count. Tuist-backed runs reject a missing result bundle or zero executed
tests.

Run the core, integration, and combined behavior schemes for complete hosted coverage:

```bash
scripts/test-runner.py run TheInsideJobTests --selection full
scripts/test-runner.py run TheInsideJobIntegrationTests --selection full
scripts/test-runner.py run HostedBehaviorTests --selection full
```

CI preserves build-once execution without owning Xcode arguments:

```bash
scripts/test-runner.py build-for-testing TheInsideJobTests
scripts/test-runner.py test-without-building TheInsideJobTests
```

## Topology 2: external driver

A CI step boots a simulator, launches the app with the embedded server
configured through environment variables, and drives it with the `buttonheist`
CLI. Use this when the flows live as `.heist` artifacts or when the driver is
an agent rather than a test bundle.

```bash
# One slug names everything this job owns: simulator, token, instance ID.
SLUG="ci-${CI_JOB_ID:-local}-checkout"
PORT=$((RANDOM % 10000 + 20000))

# Boot a dedicated simulator.
SIM_UDID=$(xcrun simctl create "$SLUG" "iPhone 16 Pro")
xcrun simctl boot "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID" -b

# Install the debug build that links TheInsideJob, then launch it with an
# explicit port and token. simctl forwards SIMCTL_CHILD_* variables into the
# app process.
xcrun simctl install "$SIM_UDID" path/to/YourApp.app
SIMCTL_CHILD_INSIDEJOB_PORT="$PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$SLUG" \
xcrun simctl launch "$SIM_UDID" com.example.yourapp

# Drive it. Simulator loopback needs no Bonjour, which CI machines often
# block anyway — connect directly by host:port.
export BUTTONHEIST_DEVICE="127.0.0.1:$PORT"
export BUTTONHEIST_TOKEN="$SLUG"

buttonheist run_heist --path Heists/Checkout.heist --junit report.xml
STATUS=$?

# Teardown.
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
exit $STATUS
```

`run_heist --junit` writes a JUnit XML report, so any CI system that ingests
JUnit can render heist steps as test results.

### Parallel jobs

Each job must own its simulator, port, and token. The convention is one
human-readable slug for all three — simulator name = token = instance ID —
so `xcrun simctl list devices booted` reads as a dashboard of running jobs and
an auth failure names whose session you hit. Ports are per-job; pick from a
range or let each job derive one. The full convention and its rationale are in
[Authentication](AUTH.md).

### Compiling artifacts in CI

To validate authored Swift heists without running them, compile in a build
step:

```bash
swift build --product heist-plan
HEIST_THEPLANS_BUILD_DIR=.build/debug \
  heist-plan compile Heists/Checkout.swift --entry makeCheckoutHeist --output Checkout.heist
```

Artifact resolution options and diagnostics are covered in
[Swift heist authoring](SWIFT-HEIST-AUTHORING.md#compilation-boundary).

Validate the generated artifact without booting a simulator or establishing a
Button Heist session:

```bash
buttonheist validate_heist --path Checkout.heist --lint strict_test --format json
```

The command exits nonzero when the plan or root invocation is inadmissible, or
when the selected lint mode emits an error. Lint warnings do not change the
exit status. The same command is available through JSON-lines and MCP.

## Which topology when

| Situation | Topology |
|-----------|----------|
| Heists are regression tests for one app | App-hosted — failures land in the suite that owns the screen |
| Flows stored as `.heist` artifacts, replayed across builds | External driver |
| An agent explores or authors in CI | External driver |
| System dialogs or other-process surfaces in the flow | Pair with an out-of-process shell such as XCUITest; Button Heist still asserts only app-owned surfaces. See [Scope and limits](SCOPE-AND-LIMITS.md) |
