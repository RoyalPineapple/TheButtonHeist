# CI integration

Heists run in CI in two topologies. Pick by where the test logic should live:
inside the app's own test bundle, or in a runner script that drives the app
from outside.

Both topologies share the version rule: the embedded `TheInsideJob` build and
the `buttonheist` CLI/MCP build must be the same release. The wire handshake
compares versions for exact equality and rejects mismatches, so pin the CLI to
the release your app embeds rather than installing "latest" in CI.

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
                .expect(.appeared(.label("Payment Complete")))
        }
    }
}
```

For app-hosted targets that share teardown machinery with synchronous test
suites, use `runHeistSync` (see
[Swift heist authoring](SWIFT-HEIST-AUTHORING.md)). Failures report through
`XCTFail` at the call site, so heist failures appear in your runner's normal
test results — no separate report plumbing.

To keep receipts as build artifacts, record them explicitly and upload the
directory:

```swift
runHeistSync("Checkout.pay", recordReceipt: .always, to: receiptsURL) {
    Activate(.label("Pay"))
        .expect(.appeared(.label("Payment Complete")))
}
```

If no URL is supplied, receipts are written under the process temporary
directory at `buttonheist-receipts/`.

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

## Which topology when

| Situation | Topology |
|-----------|----------|
| Heists are regression tests for one app | App-hosted — failures land in the suite that owns the screen |
| Flows stored as `.heist` artifacts, replayed across builds | External driver |
| An agent explores or authors in CI | External driver |
| System dialogs or other-process surfaces in the flow | Pair with an out-of-process shell; see [Scope and limits](SCOPE-AND-LIMITS.md) |
