# Heist Doctor

`heist-doctor` is an alpha, suggestion-only repair experiment for Button Heist
receipts.

It compares a last passing `HeistExecutionResult` receipt with a new failing
`HeistExecutionResult` receipt, then prints either structured repair suggestions
or structured reasons it cannot safely suggest one.

It is not automatic self-healing. It does not connect to an app, rerun a heist,
edit source, rewrite DSL, mutate `.heist` artifacts, update stored plans, or
change playback behavior.

## Current Status

Treat this as alpha.

The repair guardrails are deliberately conservative, but the workflow around
the tool is still young:

- CI receipt upload and latest-passing lookup are not turnkey yet
- the validation set is small and intentionally experimental
- confidence calibration has not been proven across broad real failures
- public `run_heist` JSON is not the same shape as the raw receipt input
- output can be verbose when the preserved hierarchy is flat or broad
- artifact retention policy still belongs to CI, not to Button Heist itself

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

Button Heist can write raw gzip receipts automatically when this environment
variable is set:

```bash
BUTTONHEIST_RECEIPTS_DIR="$CI_ARTIFACTS/buttonheist-receipts"
```

By default, only failed heist runs are recorded. To also record passing runs:

```bash
BUTTONHEIST_RECEIPTS_MODE="failing-and-passing"
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

- CI glue that uploads `BUTTONHEIST_RECEIPTS_DIR` and finds latest passing
  receipts by heist fingerprint
- enough real failure examples to tune confidence and abstention behavior
- bounded, reviewer-friendly summaries for broad hierarchy context
- a documented retention convention for latest passing and current failing
  receipts
- clarity on whether doctor should also unwrap public `run_heist` output or
  only raw receipts

Until then, keep the interface small and experimental.
