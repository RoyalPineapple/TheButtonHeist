# Heist Doctor

`heist-doctor` is an alpha, suggestion-only repair experiment for The Button Heist
results.

It projects each `HeistResult` embedded in a last passing
`HeistResultRecording` and a new failing recording into its canonical
`HeistReport`, then selects report nodes and prints either structured repair
suggestions or structured reasons it cannot safely suggest one.

It is not automatic self-healing. It does not connect to an app, rerun a heist,
edit source, rewrite DSL, mutate `.heist` artifacts, update stored plans, or
change playback behavior.

## Current Status

Treat this as public experimental, SwiftPM-only alpha. The executable is a
SwiftPM product for local and CI experiments. It is intentionally not installed
by the Homebrew formula, and its CLI flags, result heuristics, scoring, and
output JSON are not a major-version compatibility contract yet.

The repair guardrails are deliberately conservative, but the workflow around
the tool is still young:

- CI now uploads result artifacts from the main test lanes, but latest-passing
  lookup is still manual
- the validation set is small and intentionally experimental
- confidence calibration has not been proven across broad real failures
- public `run_heist` JSON is not the same shape as the recording input
- output can be verbose when the preserved hierarchy is flat or broad
- artifact retention policy still belongs to CI, not to The Button Heist itself

The safe promise is narrow: if you provide the right two result recordings, the
doctor can explain a candidate target repair or explain why it is refusing to
guess.

## Inputs

The doctor reads self-contained `HeistResultRecording` JSON files. Each
recording contains the result, plan name, plan fingerprint, recording time, and
producer version:

```bash
heist-doctor \
  --last-pass 4F6F86E1-5D1C-4CF3-83E3-61DBD07A9235.json \
  --new-fail 73B15971-0E56-44D0-8E45-BE81D19A6078.json
```

It also accepts gzip-compressed recording JSON:

```bash
heist-doctor \
  --last-pass 4F6F86E1-5D1C-4CF3-83E3-61DBD07A9235.json.gz \
  --new-fail 73B15971-0E56-44D0-8E45-BE81D19A6078.json.gz
```

For local and CI experiments, prefer gzip. In the first demo result-pair
experiment, recordings around 7-8 MB compressed to roughly 200-250 KB.

## Automatic Result Recording

The Button Heist can write self-contained gzip recordings automatically when
this environment variable is set:

```bash
BUTTONHEIST_RESULTS_DIR="$CI_ARTIFACTS/buttonheist-results"
```

By default, only failed heist runs are recorded. To also record passing runs:

```bash
BUTTONHEIST_RESULTS_MODE="all"
```

For local test runs, use the canonical runner. It applies the result wrapper and
uses the same convention as CI:

```bash
BUTTONHEIST_RESULTS_MODE=all \
  scripts/test-runner.py run ButtonHeistTests
```

The runtime writes each recording directly under the configured root:

```text
buttonheist-results/
  4F6F86E1-5D1C-4CF3-83E3-61DBD07A9235.json.gz
  73B15971-0E56-44D0-8E45-BE81D19A6078.json.gz
```

The UUID is only collision-resistant storage identity. Plan identity, execution
outcome, and recording time are decoded from the file contents. A recording
therefore remains valid if it is moved or renamed, although the pairing helper
discovers only the canonical `UUID.json` and `UUID.json.gz` names.

This hook lives at the heist execution boundary, not inside XCTest or Swift
Testing. That keeps test boilerplate at zero: in-process `Heist(...)` tests and
external `run_heist` execution can both emit the same recording artifact when
the environment is configured.

For simulator-hosted tests, use the portable temp-directory sentinel so the app
process writes inside its sandbox:

```bash
BUTTONHEIST_RESULTS_DIR="process-temporary-directory"
```

Some app-hosted XCTest launchers do not propagate runner environment variables
such as Bazel `--test_env` into the app process that runs TheInsideJob. In those
targets, either call `setenv("BUTTONHEIST_RESULTS_MODE", "all",
1)` and `setenv("BUTTONHEIST_RESULTS_DIR", "process-temporary-directory", 1)`
inside the test process before executing heists, or use the sync XCTest facade:

```swift
runHeistSync("Checkout.pay", recordResult: .always, to: resultsURL) {
    Activate(.label("Pay"))
        .expect(.elementsChanged([.appeared(.label("Payment Complete"))]))
}
```

CI can then copy the sandboxed files out with:

```bash
scripts/collect-ios-heist-results.sh "$SIM_UDID" "$RUNNER_TEMP/buttonheist-results"
```

The GitHub Actions CI currently enables this for the macOS unit-test lane, the
iOS-hosted unit-test lane, and the iOS demo smoke gates. PR runs keep failing
results by default. `main` runs keep failing and passing results so successful
main builds can act as the last-pass baseline.

To run the doctor against downloaded or local result artifacts, point the
pairing helper at the last-passing and new-failing artifact roots:

```bash
scripts/heist-doctor-from-results.sh \
  --last-pass-dir path/to/main/buttonheist-results \
  --new-fail-dir path/to/pr/buttonheist-results
```

The helper searches both roots recursively for canonical UUID-named recordings,
decodes plain JSON and gzip JSON, and pairs a passed and failed
`result.outcome` with the same decoded `planFingerprint`. It chooses the newest
eligible failed recording and its newest passing match by decoded `recordedAt`,
then invokes `heist-doctor`. Filenames and parent directories do not determine
plan identity or outcome.

XCTest and Swift Testing adapters may later add nicer test attachments or names,
but artifact collection should not depend on per-test wrappers.

## Evidence Model

The useful execution evidence is already in the recording's `HeistResult`.
`HeistReport.project(result:)` is the sole semantic interpretation; Doctor
consumes its selected action-node facts:

- step paths and nested execution structure
- authored action commands and expectations
- action result and expectation result evidence
- `Observation.Evidence` baseline/current snapshots and ordered events
- resolved subject evidence for successful actions
- failure details for the new failing action

The doctor uses that evidence to prove old intent before it looks for a
successor. If the old target did not resolve exactly once in the last passing
result, there is no safe target repair.

## Diagnosis Pipeline

The `heist-doctor` executable runs the suggestion flow as a typed diagnosis:

```text
evidence eligibility -> candidate ranking -> candidate validation -> suggestion or refusal
```

Its internal core accepts already-extracted repair evidence or result pairs and
records validated suggestions, ranked candidate diagnostics, and typed refusal
facts. The supported interface is the executable's human or JSON output; the
core model types are implementation details, not an SDK surface.

The artifact boundary stays deliberately boring for now:

```text
The Button Heist run -> UUID.json.gz (HeistResultRecording) -> CI artifact
last-pass artifact + new-fail artifact -> heist-doctor
```

There is no custom evidence-pack format, no product-owned result database, no
visual snapshot store, and no runtime repair sidecar. Compressed recordings are
small enough for current CI experiments and preserve the full evidence shape
for future doctor work. If size, privacy, or processing cost becomes a real
constraint, the next format can be designed from measured data instead of
guesswork.

## Repair Rules

The current alpha should keep these rules:

- suggestions require semantic continuity, not just matching role or action
- duplicate candidates require local context such as row, sibling, header, or
  stable container evidence
- a suggested matcher must resolve exactly once in the current failing result
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

- latest passing result lookup by heist fingerprint
- enough real failure examples to tune confidence and abstention behavior
- bounded, reviewer-friendly summaries for broad hierarchy context
- a documented retention convention for latest passing and current failing
  results
- clarity on whether doctor should also unwrap public `run_heist` output or
  only self-contained recordings

Until then, keep the interface small and experimental.
