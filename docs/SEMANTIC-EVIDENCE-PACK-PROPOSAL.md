# Heist Execution Evidence Proposal

Draft proposal for long-term heist durability and evidence-driven repair.

## Summary

Do the simple thing first: log the full `HeistExecutionResult` as a compressed
CI artifact.

`HeistExecutionResult` already contains the repair substrate:

- step tree and step paths
- authored action commands and expectations
- action results and expectation results
- accessibility traces with before/after captures
- subject evidence for resolved actions
- loop and invocation evidence
- failure details

For the current alpha repair experiment, `heist-doctor` should keep reading
these receipts directly. Only introduce a separate compact evidence-pack format
if raw compressed receipts prove too large, too repetitive, or too sensitive in
practice.

## Principle

Do not over-optimize the evidence format before we have real usage.

The runtime already emits the semantic evidence we need. CI already knows how to
store artifacts. The doctor already knows how to consume `HeistExecutionResult`.

So the v0 product boundary should be:

```text
Button Heist run -> HeistExecutionResult.json.gz -> CI artifact
last-pass artifact + new-fail artifact -> heist-doctor
```

No new repair API. No new storage service. No custom snapshot pack yet.

## Why This Is Enough For v0

The first real doctor experiment suggests full receipts are cheap enough once
compressed:

| Receipt | Raw JSON | Gzip |
|---------|----------|------|
| Last pass | 8.3 MB | 247 KB |
| New fail | 7.0 MB | 208 KB |

That is well within normal CI artifact budgets. It is not worth designing a
content-addressed snapshot store until real CI data shows a problem.

The raw receipts also have an important durability advantage: they preserve the
complete evidence shape available today. If the doctor gets smarter, it can
reprocess old receipts without being limited by an early compact projection.

## v0 Artifact

For each heist run, write:

```text
heist-execution-result.json.gz
```

The uncompressed payload is the existing `HeistExecutionResult` JSON.

Suggested naming:

```text
buttonheist/<heist-fingerprint>/<run-id>/heist-execution-result.json.gz
```

For local debugging, the same output can be written to a caller-supplied path:

```bash
BUTTONHEIST_RECEIPTS_DIR=.buttonheist-receipts buttonheist run-heist ...
```

Naming can change, but the payload should stay boring: gzip-compressed
`HeistExecutionResult`.

## CI Retention

Suggested policy:

- Always upload failing-run receipts.
- Upload passing receipts for protected branches.
- Keep the latest passing receipt per heist fingerprint on `main`.
- Keep PR receipts for normal CI retention windows.
- Optionally keep a small rolling history for flake and research analysis.

The product should not own long-term historical storage. CI already has the
right lifecycle and permissions.

## Doctor Flow

`heist-doctor` should continue to support direct receipt input:

```bash
heist-doctor \
  --last-pass last-green.heist-execution-result.json.gz \
  --new-fail current-fail.heist-execution-result.json.gz
```

It can transparently accept either plain JSON or `.gz` JSON.

The doctor algorithm remains:

1. Match heist fingerprint and step path when available.
2. Load the last-pass before trace and prove the old target resolved exactly
   once.
3. Load the current-fail before trace and classify the failure:
   `missing`, `ambiguous`, `wrong capability`, or `no target repair needed`.
4. Derive local semantic neighborhoods from the preserved hierarchy.
5. Rank candidates using semantic continuity:
   identifier, label/value continuity, row/header/sibling/container context,
   actions/traits, and optional after-diff evidence.
6. Generate the minimum unique matcher in the current-fail snapshot.
7. Emit a suggestion or a structured refusal.

All repair intelligence stays in the alpha CLI.

## Privacy And Safety

Raw receipts may include user-facing labels/values, geometry, and activation
points. Treat them like test logs.

Safety rules:

- Do not use geometry, activation points, runtime IDs, capture IDs, or generated
  IDs in suggested matchers.
- Do not auto-edit heists or stored artifacts.
- Do not upload screenshots/video as part of this v0 path.
- Add redaction only when a real test environment requires it.

If raw receipts become too sensitive for broad retention, solve that with a
redaction pass before inventing a new repair model.

## What Not To Build Yet

Do not build these until v0 proves they are needed:

- content-addressed snapshot store
- custom evidence-pack zip format
- separate compact semantic snapshot schema
- runtime repair sidecar
- product-owned receipt database
- visual or geometry evidence retention

These may become useful later, but they are premature for the first durable
repair loop.

## v1 Escalation Criteria

Consider a compact evidence-pack format only if we observe one of these:

- compressed receipts are too large for CI retention at normal scale
- repeated captures make artifact retrieval or processing slow
- privacy review requires default geometry stripping
- old receipts lack enough structure because the raw trace shape is too tied to
  current wire models
- doctor performance needs precomputed snapshot indexes

Until then, compressed `HeistExecutionResult` is the right artifact.

## Minimal Implementation

1. Make `heist-doctor` read both `.json` and `.json.gz` receipts.
2. Add a CI/test-runner path to write `HeistExecutionResult.json.gz`.
   The low-boilerplate shape is `BUTTONHEIST_RECEIPTS_DIR`, with
   `BUTTONHEIST_RECEIPTS_MODE=failing-and-passing` when pass receipts are
   desired.
3. CI now uploads receipt artifacts from the main test lanes. PR runs keep
   failing receipts; `main` runs keep failing and passing receipts.
4. Use `scripts/heist-doctor-from-receipts.sh` to match downloaded artifacts by
   heist fingerprint and run the doctor.
5. Keep the existing doctor repair output unchanged.
6. Measure artifact sizes in real CI before doing anything smarter.

## Recommendation

Start with compressed `HeistExecutionResult` artifacts.

That gives us the repair data, keeps the product surface small, and avoids
locking in an optimized evidence format before we know the actual constraints.
The design can still evolve toward compact content-addressed snapshots later,
but only when the data says the simpler path is not enough.
