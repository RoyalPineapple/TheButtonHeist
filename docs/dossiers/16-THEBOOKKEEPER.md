# TheBookKeeper - The Accountant

> **File:** `ButtonHeist/Sources/TheButtonHeist/TheBookKeeper.swift`
> **Platform:** macOS 14.0+
> **Role:** Centralized file operations — session logs, artifact storage, compression, path safety

## Responsibilities

TheBookKeeper owns all filesystem I/O on the macOS side:

1. **Session log** — append-only JSONL file recording every command dispatched through TheFence and every response returned, with timestamps and request IDs
2. **Artifact storage** — writes screenshots (PNG) and videos (MP4) to organized session directories with deterministic, sequence-numbered filenames
3. **Path validation** — single entry point for output path safety checks (rejects `..` components, resolves via `.standardized`)
4. **Manifest tracking** — maintains a `manifest.json` listing every artifact written during the session, with type, size, timestamp, and the command that produced it
5. **Compression** — gzips session logs on close via `/usr/bin/gzip`; bundles a completed session directory into a `.tar.gz` archive on demand via `/usr/bin/tar`
6. **Lifecycle** — creates session directory on `beginSession`, closes and compresses on `closeSession`, archives on `archiveSession`

## Architecture Diagram

```mermaid
graph TD
    subgraph BookKeeper["TheBookKeeper (@ButtonHeistActor)"]
        Session["SessionPhase State Machine"]
        Logger["Session Logger<br/>append-only JSONL"]
        Writer["Artifact Writer<br/>PNG, MP4, JSON"]
        Validator["Path Validator<br/>traversal checks"]
        Compressor["Compressor<br/>gzip, tar.gz"]
        Manifest["Manifest<br/>artifact index"]
    end

    TheFence["TheFence"] -->|"logCommand / logResponse"| Logger
    TheFence -->|"writeScreenshot / writeRecording"| Writer
    TheFence -->|"writeToPath / validateOutputPath"| Validator
    Writer --> Manifest
    Logger -->|"closeSession"| Compressor
    TheFence -->|"archiveSession"| Compressor
```

## Session State Machine

TheBookKeeper models its lifecycle as an explicit enum state machine with associated data per phase. Each phase carries exactly the data valid for that state — no stale handles, no orphaned resources.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Active : beginSession(identifier:)
    Active --> Active : logCommand / logResponse / writeArtifact
    Active --> Closed : closeSession → flush + gzip log
    Closed --> Archived : archiveSession → tar.gz bundle
    Closed --> Active : beginSession (new session)
    Archived --> Active : beginSession (new session)
```

```swift
enum SessionPhase {
    case idle
    case active(ActiveSession)
    case closed(ClosedSession)
    case archived(ArchivedSession)
}

struct ActiveSession {
    let sessionId: String              // "{identifier}-{YYYY-MM-dd-HHmmss}"
    let directory: URL                 // base/sessions/{sessionId}/
    let logHandle: FileHandle          // session.jsonl (append mode)
    var manifest: SessionManifest      // in-memory, flushed on each artifact write
    let startTime: Date
    var nextSequenceNumber: Int        // monotonic counter for artifact filenames
}

struct ClosedSession {
    let sessionId: String
    let directory: URL
    let compressedLogPath: URL         // session.jsonl.gz
    let manifest: SessionManifest
    let startTime: Date
    let endTime: Date
}

struct ArchivedSession {
    let archivePath: URL               // {sessionId}.tar.gz
    let manifest: SessionManifest
    let startTime: Date
    let endTime: Date
}
```

Transitioning from `.active` to `.closed` flushes the manifest, closes the FileHandle, and compresses the log to `.gz` via `/usr/bin/gzip`. Transitioning from `.closed` to `.archived` bundles the directory via `/usr/bin/tar czf`. No phase carries stale handles or open resources from a prior phase.

Invalid transitions throw `BookKeeperError.invalidPhase` — you cannot close an idle session, archive an active session, or begin a second session while one is active.

## Error Handling

```swift
enum BookKeeperError: Error, LocalizedError {
    case invalidPhase(expected: String, actual: String)
    case unsafePath(String)
    case base64DecodingFailed
    case compressionFailed(String)
    case archiveFailed(String)
}
```

## Session Directory Layout

```
$XDG_DATA_HOME/buttonheist/sessions/
└── accra-scroll-detection-2026-04-02-143022/
    ├── session.jsonl.gz          # compressed session log
    ├── manifest.json             # artifact index
    ├── screenshots/
    │   ├── 001-get_screen.png
    │   ├── 002-get_screen.png
    │   └── ...
    └── recordings/
        ├── 001-stop_recording.mp4
        └── ...
```

- Session directory name: `{identifier}-{YYYY-MM-dd-HHmmss}` — self-documenting, matches the simulator naming convention.
- Artifacts use a zero-padded 3-digit sequence number prefix + the command raw value that produced them (`001-get_screen.png`). Sequence numbers are monotonic and never collide; timestamps are in the manifest.
- Base directory resolution follows XDG Base Directory conventions:
  1. `BUTTONHEIST_SESSIONS_DIR` env var (explicit override, highest priority)
  2. `$XDG_DATA_HOME/buttonheist/sessions/` (XDG-compliant)
  3. `~/.local/share/buttonheist/sessions/` (XDG default when `XDG_DATA_HOME` is unset)
- No `~/Library/Application Support/` — this is a CLI tool, not a sandboxed app.

The `init(baseDirectory:)` parameter overrides all env var resolution, used by tests to write into a temp directory.

## Session Log Format

Append-only JSONL. One JSON object per line. Two record types:

```jsonl
{"command":"activate","requestId":"abc-123","t":"2026-04-02T14:30:22.451Z","type":"command","args":{"identifier":"loginButton"}}
{"duration_ms":441,"requestId":"abc-123","status":"ok","t":"2026-04-02T14:30:22.892Z","type":"response"}
{"command":"get_screen","requestId":"def-456","t":"2026-04-02T14:30:25.100Z","type":"command"}
{"artifact":"screenshots/001-get_screen.png","duration_ms":580,"requestId":"def-456","status":"ok","t":"2026-04-02T14:30:25.680Z","type":"response"}
```

Fields:
- `t` — ISO 8601 timestamp with fractional seconds
- `type` — `"command"` or `"response"`
- `requestId` — correlates command/response pairs
- `command` — the `TheFence.Command` raw value (command records only)
- `args` — the request arguments, minus binary data and the `"command"` key itself (command records only; omitted when empty)
- `status` — `"ok"` or `"error"` (response records only)
- `duration_ms` — wall-clock time from command to response (response records only)
- `artifact` — relative path to any file written (response records only, when applicable)
- `error` — error message (response records only, when status is `"error"`)

Binary data exclusion: keys in the `binaryKeys` set (`pngData`, `videoData`) are stripped. String values longer than 1000 characters are replaced with a `<N chars>` placeholder. JSON keys are sorted for deterministic output.

## Manifest Format

```json
{
    "sessionId": "accra-scroll-detection-2026-04-02-143022",
    "startTime": "2026-04-02T14:30:22Z",
    "endTime": "2026-04-02T14:31:45Z",
    "artifacts": [
        {
            "type": "screenshot",
            "path": "screenshots/001-get_screen.png",
            "size": 245760,
            "timestamp": "2026-04-02T14:30:25Z",
            "requestId": "def-456",
            "command": "get_screen",
            "metadata": { "width": 393.0, "height": 852.0 }
        },
        {
            "type": "recording",
            "path": "recordings/001-stop_recording.mp4",
            "size": 3145728,
            "timestamp": "2026-04-02T14:31:40Z",
            "requestId": "ghi-789",
            "command": "stop_recording",
            "metadata": { "width": 393, "height": 852, "duration": 12.5, "fps": 8, "frameCount": 100 }
        }
    ],
    "commandCount": 47,
    "errorCount": 2
}
```

The manifest is flushed to disk atomically (via `Data.write(to:options:.atomic)`) after every artifact write and on session close. It uses pretty-printed JSON with sorted keys.

## Compression

Two levels, both shelling out to standard POSIX utilities via `Process`:

1. **Log compression** (`closeSession`) — `/usr/bin/gzip session.jsonl` → `session.jsonl.gz`. gzip replaces the original file atomically. Verifies the `.gz` file exists after completion; throws `BookKeeperError.compressionFailed` on non-zero exit or missing output.

2. **Session archive** (`archiveSession`) — `/usr/bin/tar czf {sessionId}.tar.gz -C {parent} {dirName}`. The archive is written adjacent to the session directory. Verifies the archive exists; throws `BookKeeperError.archiveFailed` on failure. Optionally deletes the source directory via `deleteSource` parameter.

### Output format contract

Every file TheBookKeeper writes is consumable by standard Unix tools without Apple software:

| Artifact | Format | Verify with |
|----------|--------|-------------|
| Session log | JSONL (one JSON object per `\n`-terminated line) | `jq . < session.jsonl` |
| Compressed log | gzip (RFC 1952) | `gunzip session.jsonl.gz` |
| Manifest | JSON | `jq . < manifest.json` |
| Screenshots | PNG | `file 001-get_screen.png` |
| Recordings | MP4 (H.264) | `ffprobe 001-stop_recording.mp4` |
| Session archive | tar+gzip | `tar xzf session.tar.gz` |

No `.plist`, no `.bplist`, no Apple Archive (`.aar`), no Compression framework raw streams. `scp` a session archive to a Linux box, `tar xzf` it, `gunzip` the log, `jq` the manifest — everything works.

## Integration with TheFence

TheFence owns TheBookKeeper as a `let` property alongside TheHandoff:

```swift
let handoff = TheHandoff()
let bookKeeper = TheBookKeeper()
```

### Commands

Two local-only commands dispatch to TheBookKeeper without sending anything to the iOS device:

| Command | Enum case | Behavior |
|---------|-----------|----------|
| `get_session_log` | `.getSessionLog` | Returns the current `SessionManifest` as a `.sessionLog` response |
| `archive_session` | `.archiveSession` | Closes and archives the session, returns `.archiveResult` with the archive path |

Both are in the no-connection-required guard alongside `get_session_state`, `list_devices`, `connect`, and `list_targets`.

### FenceResponse cases

```swift
case sessionLog(manifest: SessionManifest)
case archiveResult(path: String, manifest: SessionManifest)
```

Both implement `humanFormatted()`, `compactFormatted()`, and `jsonDict()`.

### Logging integration (planned)

TheFence's `execute(request:)` is the hook point for wrapping dispatch with log calls. The API is ready — `logCommand` and `logResponse` silently no-op when the phase is `.idle`, so wiring them in has no effect until a session is begun.

### File write delegation (planned)

TheFence handlers `handleGetScreen` and `handleStopRecording` still write files inline via `Data.write(to:)` with duplicated path-traversal guards. The plan is to delegate these to `bookKeeper.writeToPath` and `bookKeeper.writeScreenshot`/`writeRecording`, removing the duplicated `..` checks from handlers.

## CLI Commands

```
buttonheist session-log              # Print session manifest and stats
buttonheist archive-session          # Close + archive current session → prints archive path
  --delete-source                    # Remove session directory after archiving
```

Both accept `--format` (human/json/compact) and standard `ConnectionOptions`.

## MCP Tools

```json
{
    "name": "get_session_log",
    "description": "Get the current session manifest showing all commands executed and artifacts produced during this session.",
    "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false }
}
```

```json
{
    "name": "archive_session",
    "description": "Close and compress the current session into a .tar.gz archive. Returns the archive file path.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "delete_source": {
                "type": "boolean",
                "description": "Delete the session directory after archiving (default: false)"
            }
        },
        "additionalProperties": false
    }
}
```

## Design Decisions

### Portable artifacts, modern implementation

The implementation uses idiomatic Swift — `FileHandle`, `FileManager`, `JSONEncoder`, `JSONSerialization`, `Data`, `URL`. The constraint is on **what hits disk**: every output artifact is a standard format consumable by Unix tools without Apple software.

- **XDG Base Directory** for session storage, not `~/Library/Application Support/`. This is a CLI tool used by developers and agents.
- **gzip (RFC 1952)** for log compression via `/usr/bin/gzip`, not Apple Archive or Compression framework.
- **tar+gzip** for session archives via `/usr/bin/tar`. Standard, universal.
- **JSONL and JSON** for structured data, not plist.
- **PNG and MP4** for media — passed through as-is from the wire.

### Why a separate crew member, not inline in TheFence?

TheFence is the largest type in the codebase (600+ lines). File I/O, compression, and manifest management are a distinct responsibility. Extracting them follows the same pattern that separated TheHandoff (connection lifecycle) from TheFence (command dispatch).

### Why JSONL?

Append-only (safe for crash recovery), streamable (`jq` works line-by-line), compresses well. Each line is independently parseable — a truncated file loses at most one partial entry.

### Why lazy session creation?

One-shot CLI commands (`buttonheist screenshot --output shot.png`) don't need session directories. TheBookKeeper starts in `.idle` and only allocates a directory when `beginSession` is called. `writeToPath` works without a session for explicit caller-specified paths. `logCommand`/`logResponse` silently no-op in idle.

### Why sequence numbers instead of timestamps in filenames?

Timestamps can collide (two screenshots in the same second). Sequence numbers are monotonic and sort naturally. The timestamp is in the manifest and the log.

### Why not compress recordings?

MP4 (H.264) is already compressed. Gzipping an MP4 saves <1%.

## Tests

25 tests in `TheBookKeeperTests.swift`, using real filesystem I/O against a temp directory that is created in `setUp` and deleted in `tearDown`.

| Group | Tests | What they verify |
|-------|-------|-----------------|
| Session phase | 9 | idle→active→closed→archived transitions, invalid transitions throw, new session from closed/archived |
| Session log | 6 | JSONL line format, command/response fields, error count, command count, binary data exclusion, silent no-op when idle |
| Manifest | 2 | Starts empty with zero counts, Codable round-trip equality |
| Path validation | 5 | `..` rejection, empty path, simple relative, absolute, embedded traversal |
| Artifact storage | 6 | Screenshot/recording file creation, manifest updates, sequence numbering, base64 failure, `writeToPath` traversal guard |

TheFenceTests also updated: command count assertion (36→38), new raw value entries for `get_session_log` and `archive_session`.

## File Inventory

| File | Purpose |
|------|---------|
| `ButtonHeist/Sources/TheButtonHeist/TheBookKeeper.swift` | State machine, session lifecycle, artifact storage, path validation, public API |
| `ButtonHeist/Sources/TheButtonHeist/TheBookKeeper+Logging.swift` | JSONL log writing, binary data exclusion, command/response serialization |
| `ButtonHeist/Sources/TheButtonHeist/TheBookKeeper+Compression.swift` | `/usr/bin/gzip` for logs, `/usr/bin/tar czf` for archives |
| `ButtonHeist/Sources/TheButtonHeist/SessionManifest.swift` | `SessionManifest`, `ArtifactEntry`, `ArtifactType`, `ScreenshotMetadata`, `RecordingMetadata`, `ResponseStatus` |
| `ButtonHeist/Tests/ButtonHeistTests/TheBookKeeperTests.swift` | 25 unit tests |
| `ButtonHeistCLI/Sources/Commands/SessionLogCommand.swift` | CLI: `buttonheist session-log` |
| `ButtonHeistCLI/Sources/Commands/ArchiveSessionCommand.swift` | CLI: `buttonheist archive-session` |
