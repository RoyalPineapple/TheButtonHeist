# Data Ownership

Button Heist tracks **source-of-truth state only at ownership boundaries.**
Everything else is a short-lived index, a request correlation, a lifecycle
phase, a durable artifact, or final output formatting — never a second
worldview that can drift from the first.

This file is the contract. Before adding any new long-lived map, table, cache,
or ledger, find the owner below that already holds the fact you want. If none
does, you are either (a) adding state to the wrong layer, or (b) re-deriving
something a receipt/capture/tree already carries. Both are bugs.

## The rule of one worldview

Every tracked structure must classify as **exactly one** of:

| Category | Meaning | May persist? |
|----------|---------|--------------|
| source of truth | the canonical fact, owned at one boundary | yes |
| ephemeral index | rebuilt from source every cycle, never identity | per-cycle only |
| request correlation | requestId → continuation, nothing more | until resolved/timed-out |
| lifecycle phase | an explicit state-machine value | until the next transition |
| durable artifact | bytes on disk (heists, screenshots) | yes, on disk |
| final output formatting | a wire/report view derived on demand | not stored |

If a structure does not fit exactly one row, remove it or inline it.

## Approved long-lived state owners

### 1. TheStash — the settled accessibility world model
- **Tracks:** the settled `Screen`, latest disposable `LiveCapture`, and named
  non-clean settle diagnostic evidence.
- **Why:** there must be exactly one answer to "what accessibility world do we
  believe," while live handles and diagnostics remain separate.
- **Key:** `heistId` (semantic), `TreePath` / `AccessibilityElement` (capture).
- **Lifetime:** clean settle updates settled world; live refresh replaces only
  live capture; non-clean settle records diagnostic evidence and marks settled
  world dirty without publishing a settled observation.
- **Invalidation:** live capture is last-read-wins and viewport-shaped;
  `Screen.merging(_:)` is pure last-read-wins on heistId conflict.
- **Output:** `HeistElement` / `Interface` via `get_interface` (derived on demand).

`LiveCapture` is an **ephemeral index**, not memory. Its per-path maps
(`containerNamesByPath`, `scrollableContainerViewsByPath`) exist to disambiguate
duplicate containers within a single capture and are rebuilt every parse. They
must never be treated as stable identity.

### 2. TheMuscle — auth / admission / session state inside the app
- **Owner:** `TheMuscleAdmission` (holds `TheMuscleClientRegistry`).
- **Tracks:** each client's `ClientAuthenticationState` phase
  (`connected → helloValidated → authenticated`).
- **Why:** admission is a security boundary; one place decides who is in.
- **Key:** `clientId: Int` (allocated by the transport).
- **Lifetime:** per connected client, from connect to disconnect.
- **Invalidation:** `remove(clientId)` on disconnect; `removeAll()` on teardown.
- **Output:** none — internal admission decisions only.

Transport classes do **not** own auth. See the earned-ledger note below.

### 3. TheHandoff — external connection state outside the app
- **Tracks:** `HandoffConnectionPhase` (disconnected / reconnecting / connecting
  / connected / failed) and, while discovering, a `DiscoveryRegistry`.
- **Why:** the CLI/MCP side needs one answer to "are we connected, and to what."
- **Key:** connection — the live `HandoffConnectedSession`; discovery —
  Bonjour service name + device identity.
- **Lifetime:** connection phase lives for the session; the discovery registry
  lives for a discovery scan.
- **Invalidation:** phase transitions on connect/disconnect/failure;
  `DiscoveryRegistry.recordLost` / supersession evicts stale advertisements.
- **Output:** `SessionConnectionSnapshot` (derived from the phase on demand).

### 4. PendingRequestTracker — request ID → continuation correlation
- **Owner:** `TheFence.PendingRequestTrackers` (one tracker per response type).
- **Tracks:** `requestId → awaiting continuation`. Nothing else — no results are
  cached after delivery.
- **Why:** request/response over the wire is asynchronous; the continuation has
  to be found again when the response arrives.
- **Key:** `requestId: String`.
- **Lifetime:** from `wait()` registration until `resolve()`, timeout, or
  cancellation — whichever comes first.
- **Invalidation:** the entry is removed on resolve, on timeout, and on
  cancellation (owner-scoped removal is idempotent across all orderings).
- **Output:** none — it hands the result to the awaiting caller and forgets it.

### 5. HeistExecutionResult — heist execution evidence
- **Tracks:** the full execution tree (`steps`, each with children, outcomes,
  action results, expectations).
- **Why:** the tree **is** the report. There is no second report worldview.
- **Key:** structural position in the tree.
- **Lifetime:** produced once per heist run; flows through as a value.
- **Invalidation:** immutable value — never mutated after construction.
- **Output:** report facts (status, counts, rows, JUnit XML) are **derived
  properties** on the result/step types and on output-only adapters
  (`HeistJUnitReport`). Counts, pass/fail tallies, and step rows are computed
  from the tree on demand and never stored. Flattening is an output concern and
  must not drive runtime failure logic.

### 6. HeistStore / ScreenshotStore — durable artifacts only
- **Tracks:** `.heist` files and screenshot bytes on disk.
- **Why:** artifacts outlive the process.
- **Key:** file path.
- **Lifetime:** until deleted from disk.
- **Invalidation:** filesystem.
- **Output:** the files themselves.

## Earned ledgers, not duplication

Three types match the `*Registry` name and are keyed similarly, but they are
distinct ledgers at distinct boundaries — not one concept split across names:

- **`SocketClientRegistry`** (TheInsideJob, owned by `SimpleSocketServer`):
  per-connection **transport** facts — `NWConnection` and send-buffer
  accounting. Keyed by `clientId`.
- **`TheMuscleClientRegistry`** (TheInsideJob, owned by `TheMuscleAdmission`):
  per-client **auth phase**. Keyed by the same `clientId`.
- **`DiscoveryRegistry`** (TheHandoff, owned by `DeviceDiscovery`): Bonjour
  advertisement dedup, **outside** the app. Keyed by service name + identity.

The first two share a key but live at different layers on purpose: criterion #9
(transport classes do not own auth semantics) forbids merging them. Collapsing
them would put auth state in the transport or transport state in auth.

## Task-lifetime trackers

`TaskTracker` (TheInsideJob) and `LifecycleBoundaryTasks` (TheInsideJob,
lifecycle) hold in-flight `Task` handles so callback-bridge tasks spawned from
arbitrary isolation can be cancelled/drained on teardown. They track *task
lifetime*, not product state. Key: an internal monotonic id. Invalidation: each
task self-removes on completion; `cancelAll()` / `drain()` clears the rest at
teardown.

## What this contract forbids

- A second map that mirrors another map (e.g. a name-index that duplicates an
  id-index without adding a distinct lookup axis).
- A stored count/summary/status that `HeistExecutionResult` can compute.
- Adapter-side (CLI/MCP) command tables that duplicate `FenceCommandDescriptor`.
  Both adapters derive everything from `FenceCommandRegistry.descriptors`.
- Treating an ephemeral capture index as stable identity across captures.

## Why there is no source-scanning guardrail

This contract is held by review discipline and by ownership comments at each
declaration — not by a test that greps source for forbidden names. A
filesystem-scanning test is brittle, vacuously passes on a wrong path, and reads
as ceremony. The code leads the pattern; the names and the comments at the
ownership boundaries are the enforcement.
