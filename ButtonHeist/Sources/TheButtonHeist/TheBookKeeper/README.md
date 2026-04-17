# TheBookKeeper

Session recording, artifact storage, and heist playback. All filesystem I/O in the ButtonHeist framework lives here.

## Reading order

1. **`TheBookKeeper.swift`** — The `@ButtonHeistActor final class`. Everything revolves around `SessionPhase`:

   ```
   .idle → .active(ActiveSession) → .closing(ClosingSession) → .closed(ClosedSession) → .archived(ArchivedSession)
   ```

   Each case carries exactly the data valid for that phase. `ActiveSession` holds the open `FileHandle`, the mutable `SessionManifest`, `nextSequenceNumber` (for artifact filenames), and an optional `HeistRecording`.

   **Session lifecycle:**
   - `beginSession(identifier:)` — creates `{baseDir}/{identifier}-{timestamp}/`, opens `session.jsonl`, writes a header line, transitions to `.active`.
   - `logCommand(requestId:command:arguments:)` / `logResponse(...)` — append JSONL entries. Binary keys (`pngData`, `videoData`) are stripped; strings >1000 chars are truncated.
   - `writeScreenshot(base64Data:requestId:command:metadata:)` — decodes base64, writes `screenshots/001-get_screen.png`, appends `ArtifactEntry` to manifest, flushes manifest.
   - `closeSession()` — stamps `endTime`, closes file handle, gzips the log (replaces `session.jsonl` with `session.jsonl.gz`), transitions through `.closing` → `.closed`.
   - `archiveSession(deleteSource:)` — tars the directory to `{sessionId}.tar.gz`, transitions to `.archived`.

   **Heist recording (nested inside an active session):**
   - `startHeistRecording(app:)` — opens `heist.jsonl`, creates `HeistRecording` with empty `interfaceCache`.
   - `updateInterfaceCache(_:)` — merges `[HeistElement]` by heistId (merge, not replace — the element from the old screen must survive for the step that triggered the transition).
   - `recordHeistEvidence(command:args:succeeded:)` — skips excluded commands (14 in `excludedHeistCommands`) and failures. Calls `buildStep` to construct a `HeistEvidence`, JSON-encodes it, and appends as a line.
   - `stopHeistRecording()` — reads all lines back from `heist.jsonl`, decodes into `[HeistEvidence]`, wraps in `HeistPlayback`.

   **`buildStep` targeting logic** — three paths:
   1. **heistId in cache**: calls `buildMinimalMatcher(element:allElements:)` to find the smallest unique matcher. Records the heistId and frame in `_recorded` metadata.
   2. **matcher fields in args**: constructs `ElementMatcher` directly from label/identifier/value/traits.
   3. **coordinate-only**: sets `RecordedMetadata(coordinateOnly: true)`, no target.

   **`buildMinimalMatcher`** — probes candidates in order: identifier alone → label+traits → label+identifier+traits. Each is checked via `uniquelyMatches` (iterates all elements, short-circuits at 2 matches). On ambiguity, falls back to the best-effort matcher plus a 0-based `ordinal` among all matches. State traits (`.selected`, `.notEnabled`, etc.) are filtered out — they change on interaction. UUID-containing identifiers are rejected via `isStableIdentifier`.

2. **`SessionManifest.swift`** — `SessionManifest`, `ArtifactEntry` (type + relative path + size + metadata), `ResponseStatus`, `ScreenshotMetadata`, `RecordingMetadata`.

3. **`TheBookKeeper+Logging.swift`** — `buildCommandLogEntry` / `buildResponseLogEntry` construct the JSONL dictionaries. `jsonSafeValue` recursively sanitizes `Any` values for `JSONSerialization`.

4. **`TheBookKeeper+Compression.swift`** — `compressLog` runs `/usr/bin/gzip`. `createArchive` runs `/usr/bin/tar czf`. Both use `Process` bridged to async via `withCheckedThrowingContinuation`.

5. **`PlaybackFailure.swift`** — Three failure modes during heist playback: `.fenceError`, `.actionFailed`, `.thrown`. Each carries the failed step and optional interface snapshot.

## Directory structure on disk

```
~/.local/share/buttonheist/sessions/
  {identifier}-{yyyy-MM-dd-HHmmss}/
    session.jsonl          # raw log (active phase)
    session.jsonl.gz       # compressed (after close)
    manifest.json          # artifact inventory
    heist.jsonl            # evidence (if recording)
    screenshots/
      001-get_screen.png
      002-get_screen.png
    recordings/
      003-stop_recording.mp4
```

Screenshots and recordings share one sequence counter, so files sort in interleaved chronological order.

> Full dossier: [`docs/dossiers/05-THEBOOKKEEPER.md`](../../../../docs/dossiers/05-THEBOOKKEEPER.md)
