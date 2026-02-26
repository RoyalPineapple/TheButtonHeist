# InsideJob - The Inside Operative

> **Module:** `ButtonHeist/Sources/InsideJob/`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Master coordinator of the entire iOS-side operation

## Responsibilities

InsideJob is the central hub running inside the target iOS app. It:

1. **Runs a TCP server** (`SimpleSocketServer`) listening for remote commands
2. **Broadcasts presence** via Bonjour mDNS (`_buttonheist._tcp`)
3. **Polls for UI changes** at configurable intervals (default 1s, min 0.5s)
4. **Dispatches all commands** to crew members (TheSafecracker, Stakeout, TheMuscle)
5. **Manages client subscriptions** and broadcasts hierarchy/screen updates
6. **Caches accessibility elements** with weak references for fast resolution

## Architecture Diagram

```mermaid
graph TD
    subgraph InsideJob["InsideJob (Singleton, @MainActor)"]
        Core["InsideJob.swift - Server lifecycle, message dispatch"]
        Acc["InsideJob+Accessibility.swift - Hierarchy parsing, delta computation"]
        Anim["InsideJob+Animation.swift - Animation detection, waitForIdle"]
        Poll["InsideJob+Polling.swift - Periodic hash-change polling"]
        Screen["InsideJob+Screen.swift - Screenshot capture, recording mgmt"]
        Auto["InsideJob+AutoStart.swift - @_cdecl entry point for ThePlant"]
    end

    subgraph Crew["Crew Members (Owned)"]
        Muscle["TheMuscle - Auth & Sessions"]
        Safecracker["TheSafecracker - Touch & Text"]
        StakeoutCrew["Stakeout - Recording"]
        Fingerprints["Fingerprints - Visual Feedback"]
    end

    subgraph Infra["Infrastructure"]
        Server["SimpleSocketServer - TCP listener"]
        NetService["NetService - Bonjour advertisement"]
        Parser["AccessibilitySnapshotParser - Hierarchy traversal"]
    end

    Core --> Muscle
    Core --> Safecracker
    Core --> StakeoutCrew
    Core --> Fingerprints
    Core --> Server
    Core --> NetService
    Acc --> Parser
    Poll --> Acc
    Screen --> StakeoutCrew
```

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `InsideJob.swift` | ~400 | Core lifecycle, server wiring, message dispatch |
| `InsideJob+Accessibility.swift` | ~300 | Hierarchy parsing, element conversion, delta computation |
| `InsideJob+Animation.swift` | ~180 | Animation detection, settle-waiting, post-action result |
| `InsideJob+Polling.swift` | ~80 | Periodic poll loop, debounced broadcast |
| `InsideJob+Screen.swift` | ~120 | Screen capture, recording start/stop |
| `InsideJob+AutoStart.swift` | ~50 | `@_cdecl` bridge for ObjC auto-start |

## Message Dispatch Flow

```mermaid
flowchart TD
    Receive["handleClientMessage - (22-case switch)"]

    Receive --> Auth["subscribe / ping"]
    Receive --> Query["requestInterface / requestScreen / waitForIdle"]
    Receive --> Actions["activate / increment / decrement / customAction"]
    Receive --> Touch["touchTap / touchLongPress / touchSwipe / touchDrag - touchPinch / touchRotate / twoFingerTap - touchDrawPath / touchDrawBezier"]
    Receive --> Text["typeText / editAction / resignFirstResponder"]
    Receive --> Recording["startRecording / stopRecording"]

    Actions --> Perform["performInteraction()"]
    Touch --> Perform
    Text --> Perform

    Perform --> Step1["1. stakeout.noteActivity()"]
    Step1 --> Step2["2. refreshAccessibilityData()"]
    Step2 --> Step3["3. snapshotElements() (before)"]
    Step3 --> Step4["4. TheSafecracker.execute*()"]
    Step4 --> Step5["5. actionResultWithDelta()"]
    Step5 --> Step6{"6. recording active?"}
    Step6 -->|yes| Step6a["6a. record InteractionEvent to Stakeout"]
    Step6 -->|no| Step7["7. send(.actionResult)"]
    Step6a --> Step7
```

## Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> Configured: configure(token, instanceId)
    Configured --> Running: start()
    Running --> Suspended: UIApplication.didEnterBackground
    Suspended --> Running: UIApplication.willEnterForeground
    Running --> Stopped: stop()
    Stopped --> [*]

    state Running {
        [*] --> ServerUp: SimpleSocketServer.start()
        ServerUp --> Advertising: NetService.publish()
        Advertising --> Polling: startPollingLoop()
    }

    state Suspended {
        [*] --> TearDown: stop server + Bonjour
        TearDown --> Waiting: wait for foreground
    }
```

## Update Mechanisms

Two paths trigger hierarchy broadcasts:

1. **Notification-driven** (`scheduleHierarchyUpdate`): Triggered by `UIAccessibility.elementFocusedNotification` and `voiceOverStatusDidChangeNotification`. Debounced 300ms.
2. **Polling** (`startPollingLoop`): Periodic at configurable interval (default 1s). Compares `elements.hashValue` to `lastHierarchyHash`. Only broadcasts on change.

## Items Flagged for Review

### HIGH PRIORITY

**Auth token logged in plaintext** (`InsideJob.swift:114`)
```swift
insideJobLogger.info("Auth token: \(self.muscle.authToken)")
```
The full UUID token is emitted to the system log at `info` level. Any process with log access can read it.

**`handleClientMessage` cyclomatic complexity** (`InsideJob.swift:268`)
- 22-case switch statement with `swiftlint:disable:next cyclomatic_complexity` suppression
- Each case delegates to a helper, so the individual cases are thin, but the method is a dense routing table

### MEDIUM PRIORITY

**`shouldBindToLoopback` always returns `false`** (`InsideJob.swift:98`)
```swift
private var shouldBindToLoopback: Bool { false }
```
Dead computed property. The server always binds to all interfaces. The documented `INSIDEJOB_BIND_ALL` env var is never read. This is a documentation drift issue (WIRE-PROTOCOL.md says loopback is the default for simulators).

**Magic nanosecond literals**
- `300_000_000` debounce (line 66)
- `1_000_000_000` polling interval (line 70)
- These could be named constants for clarity.

**`performInteraction` now captures interaction events during recording** (NEW)
- When `stakeout.state == .recording`, each interaction captures a full `InteractionEvent`
- This includes `interfaceBefore` and `interfaceAfter` snapshots
- On failed interactions, an extra `refreshAccessibilityData()` call is made for the after-snapshot
- The `command: ClientMessage` parameter was added to `performInteraction` — all 16 call sites updated

**No unit tests for InsideJob itself**
- The delta computation logic in `InsideJob+Accessibility.swift:194-299` is pure data transformation
- It could be extracted and tested without UIKit dependency
- Currently untested

### LOW PRIORITY

**Background/foreground lifecycle**
- `suspend()` tears down the entire TCP server and Bonjour advertisement
- `resume()` recreates on a new port
- Any connected clients are silently disconnected with no notification
- This is expected iOS behavior but worth understanding

**Singleton pattern**
- `InsideJob.shared` is a replaceable singleton via `configure()`
- Multiple calls to `configure()` create a new instance, but `start()` on the old one isn't called
- Safe in practice (ThePlant only calls once), but the API allows misuse
