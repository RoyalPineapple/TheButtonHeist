# TheFence

Command dispatch hub. Routes 42 commands between CLI/MCP callers and the iOS device.

## Reading order

1. **`TheFence+CommandCatalog.swift`** — `Command: String, CaseIterable` enum with 42 cases. Raw values are the wire strings (`listDevices = "list_devices"`, etc.). This is the single source of truth for the command catalog.

2. **`TheFence.swift`** — The `@ButtonHeistActor final class`. Start at `execute(request:)` — every command enters here.

   The execute path:
   1. Parse `command` string → `Command(rawValue:)`. Unknown → `.error`.
   2. Auto-connect if needed (most commands require a connection; 8 are exempt).
   3. `bookKeeper.logCommand(requestId:command:arguments:)` — log before dispatch.
   4. Fast-path expectation check: if a background delta already satisfies the `expect` field, skip the action entirely.
   5. `dispatch(command:args:)` — the big switch that routes to handlers.
   6. Log response, update interface cache, record heist evidence.
   7. Expectation validation: implicit delivery check + user-supplied `expect` field.

   Key stored state: `handoff` (TheHandoff), `bookKeeper` (TheBookKeeper), three `PendingRequestTracker<T>` instances for action/interface/screen responses, `lastInterfaceCache` for heist recording.

3. **`TheFence+Handlers.swift`** — Per-command handler implementations. Most follow the same pattern: parse args via `Dictionary+ArgParsing` → build a `ClientMessage` → call `sendAction(_:)`. `sendAction` calls `sendAndAwait` which does `handoff.send(message, requestId:)` then suspends on `actionTracker.wait(requestId:timeout:)`.

4. **`TheFence+Formatting.swift`** — `FenceResponse` enum (18 cases) with `humanFormatted()`, `compactFormatted()`, and `jsonDict()` methods. Also defines `InterfaceDetail` (`.summary`/`.full`), `BatchStepSummary`, and `NetDeltaAccumulator` (merges deltas across batch steps).

5. **`TheFence+ParameterSpec.swift`** — `FenceParameterSpec` structs declaring each command's parameters (type, required). Used by MCP to auto-generate tool schemas. `MCPExposure` controls whether a command is a direct MCP tool, grouped under a parent tool, or REPL-only.

6. **`Dictionary+ArgParsing.swift`** — `[String: Any]` extension with typed accessors: `.string("key")`, `.integer("key")`, `.boolean("key")`, `.number("key")`, `.unitPoint("startX", "startY")`.

## How TheFence talks to its crew

**TheHandoff** — owned directly (`let handoff = TheHandoff()`). TheFence sets callbacks (`onInterface`, `onActionResult`, `onScreen`) that resolve the pending request trackers. Sends messages via `handoff.send(_:requestId:)`. Reads state via `handoff.isConnected`, `handoff.connectedDevice`, etc.

**TheBookKeeper** — owned directly (`let bookKeeper = TheBookKeeper()`). TheFence passes `command.rawValue` (String) at every call site — TheBookKeeper has no dependency on `TheFence.Command`. Session log entries are written with `logCommand`/`logResponse`, artifacts with `writeScreenshot`/`writeRecording`, heist evidence with `recordHeistEvidence(command:args:succeeded:)`.

> Full dossier: [`docs/dossiers/03-THEFENCE.md`](../../../../docs/dossiers/03-THEFENCE.md)
