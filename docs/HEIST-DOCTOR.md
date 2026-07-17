# Heist Doctor

`heist-doctor` is an alpha, suggestion-only repair experiment for The Button Heist
receipts.

It compares a last passing `HeistExecutionResult` receipt with a new failing
`HeistExecutionResult` receipt, then prints either structured repair suggestions
or structured reasons it cannot safely suggest one.

It is not automatic self-healing. It does not connect to an app, rerun a heist,
edit source, rewrite DSL, mutate `.heist` artifacts, update stored plans, or
change playback behavior.

## Current Status

Treat this as public experimental, SwiftPM-only alpha. The executable is a
SwiftPM product for local and CI experiments. It is intentionally not installed
by the Homebrew formula, and its CLI flags, receipt heuristics, scoring, and
output JSON are not a major-version compatibility contract yet.

The repair guardrails are deliberately conservative, but the workflow around
the tool is still young:

- CI now uploads receipt artifacts from the main test lanes, but latest-passing
  lookup is still manual
- the validation set is small and intentionally experimental
- confidence calibration has not been proven across broad real failures
- public `run_heist` JSON is not the same shape as the raw receipt input
- output can be verbose when the preserved hierarchy is flat or broad
- artifact retention policy still belongs to CI, not to The Button Heist itself

The safe promise is narrow: if you provide the right two raw receipts, the doctor
can explain a candidate target repair or explain why it is refusing to guess.

## Inputs

The doctor reads raw `HeistExecutionResult` JSON receipts:

```bash
heist-doctor \
  --last-pass last-pass.json \
  --new-fail new-fail.json
```

It also accepts gzip-compressed JSON by file extension:

```bash
heist-doctor \
  --last-pass last-pass.json.gz \
  --new-fail new-fail.json.gz
```

For local and CI experiments, prefer gzip. In the first demo receipt-pair
experiment, raw receipts around 7-8 MB compressed to roughly 200-250 KB.

## Automatic Receipt Recording

The Button Heist can write raw gzip receipts automatically when this environment
variable is set:

```bash
BUTTONHEIST_RECEIPTS_DIR="$CI_ARTIFACTS/buttonheist-receipts"
```

By default, only failed heist runs are recorded. To also record passing runs:

```bash
BUTTONHEIST_RECEIPTS_MODE="failing-and-passing"
```

For local test runs, prefer the wrapper so the convention is the same as CI:

```bash
scripts/run-with-heist-receipts.sh \
  --suite local-tuist \
  --mode failing-and-passing \
  -- tuist test ButtonHeistTests --no-selective-testing
```

The runtime writes files under a heist-name and plan-fingerprint directory:

```text
buttonheist-receipts/
  checkout-flow-<fingerprint>/
    <timestamp>-<pid>-<uuid>-failed.json.gz
```

This hook lives at the heist execution boundary, not inside XCTest or Swift
Testing. That keeps test boilerplate at zero: in-process `Heist(...)` tests and
external `run_heist` execution can both emit the same raw receipt artifact when
the environment is configured.

For simulator-hosted tests, use the portable temp-directory sentinel so the app
process writes inside its sandbox:

```bash
BUTTONHEIST_RECEIPTS_DIR="process-temporary-directory"
```

Some app-hosted XCTest launchers do not propagate runner environment variables
such as Bazel `--test_env` into the app process that runs TheInsideJob. In those
targets, either call `setenv("BUTTONHEIST_RECEIPTS_MODE", "failing-and-passing",
1)` and `setenv("BUTTONHEIST_RECEIPTS_DIR", "process-temporary-directory", 1)`
inside the test process before executing heists, or use the sync XCTest facade:

```swift
runHeistSync("Checkout.pay", recordReceipt: .always, to: receiptsURL) {
    Activate(.label("Pay"))
        .expect(.changed(.elements([.appeared(.label("Payment Complete"))])))
}
```

CI can then copy the sandboxed files out with:

```bash
scripts/collect-ios-heist-receipts.sh "$SIM_UDID" "$RUNNER_TEMP/buttonheist-receipts"
```

The GitHub Actions CI currently enables this for the macOS unit-test lane, the
iOS-hosted unit-test lane, and the iOS demo smoke gates. PR runs keep failing
receipts by default. `main` runs keep failing and passing receipts so successful
main builds can act as the last-pass baseline.

To run the doctor against downloaded or local receipt artifacts, point the
pairing helper at the last-passing and new-failing artifact roots:

```bash
scripts/heist-doctor-from-receipts.sh \
  --last-pass-dir path/to/main/buttonheist-receipts \
  --new-fail-dir path/to/pr/buttonheist-receipts
```

The helper matches receipts by the parent heist-name/fingerprint directory,
chooses the newest failed receipt with a matching passed receipt, and invokes
`heist-doctor`.

For a deterministic demo that does not require manufacturing a red CI build:

```bash
scripts/heist-doctor-demo.sh
```

That demo generates two raw receipts through `HeistReceiptRecorder`: a last pass
where the target was `Checkout`, and a current failure where the same semantic
control is now `Go to Checkout`. CI runs this demo in the macOS test lane as a
workflow smoke test.

XCTest and Swift Testing adapters may later add nicer test attachments or names,
but artifact collection should not depend on per-test wrappers.

## Evidence Model

The useful evidence is already in `HeistExecutionResult`:

- step paths and nested execution structure
- authored action commands and expectations
- action result and expectation result evidence
- before/after accessibility traces
- resolved subject evidence for successful actions
- failure details for the new failing action

The doctor uses that evidence to prove old intent before it looks for a
successor. If the old target did not resolve exactly once in the last passing
receipt, there is no safe target repair.

## Diagnosis Pipeline

The repair engine now exposes the suggestion flow as a typed diagnosis:

```text
evidence eligibility -> candidate ranking -> candidate validation -> suggestion or refusal
```

`HeistDoctor.diagnosis(for:)` accepts already-extracted repair evidence.
`HeistDoctor.diagnosis(lastPass:newFail:stepPath:)` runs the same pipeline from
receipt pairs. Both return `HeistRepairDiagnosis`, which records validated
suggestions, ranked candidate diagnostics, and typed refusal facts.

Diagnosis is the public product. Callers that only need the rendered views read
them from the diagnosis itself: `diagnosis.suggestions` for validated repairs
and `diagnosis.noSuggestionReason` when the pipeline refused.

The artifact boundary stays deliberately boring for now:

```text
The Button Heist run -> HeistExecutionResult.json.gz -> CI artifact
last-pass artifact + new-fail artifact -> heist-doctor
```

There is no custom evidence-pack format, no product-owned receipt database, no
visual snapshot store, and no runtime repair sidecar. Raw compressed receipts
are small enough for current CI experiments and preserve the full evidence
shape for future doctor work. If size, privacy, or processing cost becomes a
real constraint, the next format can be designed from measured data instead of
guesswork.

## Repair Rules

The current alpha should keep these rules:

- suggestions require semantic continuity, not just matching role or action
- duplicate candidates require local context such as row, sibling, header, or
  stable container evidence
- a suggested matcher must resolve exactly once in the current failing receipt
- low confidence still requires real continuity evidence
- ordinal is a last resort and must be caveated
- geometry, runtime IDs, capture IDs, synthesized IDs, container handles, and
  live references must not appear in suggested matchers

Refusal is a valid result. "Unable to make a suggestion because the target is
ambiguous" is better than a plausible but unproven repair.

## What This Is Good For Now

Use it to study and manually review common semantic drift:

- label renames such as `Checkout` becoming `Go to Checkout`
- stable-identifier continuity across copy changes
- duplicated row controls when neighbor context is preserved
- wrong-capability failures where a nearby compatible successor has semantic
  continuity
- after-diff explanations for value or screen-change failures

Use the output as a repair suggestion for a human or agent to review. Do not
treat it as approval to update tests automatically.

## What Is Not Ready

Do not market or wire this as production self-healing yet.

Before calling it beta, the project needs at least:

- latest passing receipt lookup by heist fingerprint
- enough real failure examples to tune confidence and abstention behavior
- bounded, reviewer-friendly summaries for broad hierarchy context
- a documented retention convention for latest passing and current failing
  receipts
- clarity on whether doctor should also unwrap public `run_heist` output or
  only raw receipts

Until then, keep the interface small and experimental.
