# TheMuscle - The Bouncer

> **File:** `ButtonHeist/Sources/InsideJob/TheMuscle.swift`
> **Platform:** iOS 17.0+ (UIKit)
> **Role:** Guards the perimeter - authentication, session locking, on-device approval

## Responsibilities

TheMuscle controls who gets access and enforces single-driver exclusivity:

1. **Token-based authentication** - validates incoming tokens against configured/auto-generated value
2. **On-device UI approval** - shows Allow/Deny popup for empty-token connections
3. **Session locking** - ensures only one "driver" controls the app at a time
4. **Dual-timer session release** - disconnect timer + lease timer for robust cleanup
5. **Force-takeover** - allows a new driver to evict the current one

## Architecture Diagram

```mermaid
graph TD
    subgraph TheMuscle["TheMuscle (@MainActor)"]
        TokenRes["Token Resolution - explicit > env var > plist > auto-generated UUID"]
        AuthFlow["Auth Flow - validate token / show UI prompt"]
        SessionMgr["Session Manager - driver identity tracking"]
        Timers["Dual Timers - disconnect (30s) + lease (30s)"]
    end

    Client["Remote Client"] -->|authenticate(token)| AuthFlow
    AuthFlow -->|valid| SessionMgr
    AuthFlow -->|empty| UIPrompt["UIAlertController - Allow / Deny"]
    AuthFlow -->|invalid| Reject["authFailed + disconnect"]

    SessionMgr -->|same driver| Join["Join existing session"]
    SessionMgr -->|different driver| Lock["sessionLocked"]
    SessionMgr -->|force=true| Evict["Evict current driver"]

    Timers -->|all disconnected 30s| Release["releaseSession()"]
    Timers -->|no pings 30s| Release
    Release -->|invalidates token| TokenRes
```

## Auth Flow Detail

```mermaid
sequenceDiagram
    participant C as Client
    participant M as TheMuscle
    participant UI as UIAlertController

    C->>M: TCP connect
    M-->>C: authRequired

    alt Token provided and matches
        C->>M: authenticate(token: "abc123")
        M->>M: acquireSession(driverId, clientId)
        M-->>C: info(ServerInfo)
    else Token provided but wrong
        C->>M: authenticate(token: "wrong")
        M-->>C: authFailed("Invalid token")
        M->>M: disconnect after 100ms
    else Empty token (UI approval)
        C->>M: authenticate(token: "")
        M->>UI: Show "Allow connection from [client]?"
        alt User taps Allow
            UI-->>M: approved
            M-->>C: authApproved(generatedToken)
            M->>M: acquireSession
            M-->>C: info(ServerInfo)
        else User taps Deny
            UI-->>M: denied
            M-->>C: authFailed("Connection denied")
        end
    end
```

## Session Locking State Machine

```mermaid
stateDiagram-v2
    [*] --> NoSession: initial state

    NoSession --> ActiveSession: first client authenticates

    state ActiveSession {
        [*] --> SingleDriver
        SingleDriver --> MultiConnection: same driverId connects again
        MultiConnection --> SingleDriver: extra connection drops
    }

    ActiveSession --> SessionLocked: different driverId tries to connect
    SessionLocked --> ActiveSession: new driver uses forceSession=true

    ActiveSession --> DisconnectTimer: all connections drop
    DisconnectTimer --> NoSession: 30s elapsed
    DisconnectTimer --> ActiveSession: client reconnects

    ActiveSession --> LeaseTimer: no pings received
    LeaseTimer --> NoSession: 30s elapsed (also invalidates token)
    LeaseTimer --> ActiveSession: ping received
```

## Configuration

| Source | Key | Default | Notes |
|--------|-----|---------|-------|
| Environment | `INSIDEJOB_TOKEN` | auto-UUID | Explicit auth token |
| Info.plist | `InsideJobToken` | auto-UUID | Fallback to env var |
| Environment | `INSIDEJOB_SESSION_TIMEOUT` | 30s | Disconnect timer |
| Info.plist | `InsideJobSessionTimeout` | 30s | Fallback |
| Environment | `INSIDEJOB_SESSION_LEASE` | 30s | Lease timeout (min 10s) |
| Info.plist | `InsideJobSessionLease` | 30s | Fallback |

## Items Flagged for Review

### HIGH PRIORITY

**Empty token allows any network process to trigger UI prompt** (`TheMuscle.swift:108`)
- Any process on the local network can connect and send `authenticate(token: "")`
- This triggers a `UIAlertController` on the device
- Documented behavior, but potential for annoyance/DoS in shared network environments
- Consider: should there be a way to disable UI approval flow entirely?

**Lease timer invalidates auth token** (`TheMuscle.swift:294`)
- When the lease expires (no pings for 30s), `releaseSession()` is called AND the token is invalidated
- A fresh UUID is generated, meaning the previous token no longer works
- This is aggressive: if a client temporarily loses connectivity for >30s, it cannot reconnect without re-discovering the new token
- The disconnect timer does NOT invalidate the token (only the lease timer does)

### MEDIUM PRIORITY

**Repeated `100_000_000` nanosecond delay** (`TheMuscle.swift:125, 189, 249`)
```swift
try? await Task.sleep(nanoseconds: 100_000_000)  // appears 3 times
```
- Used as a "give client time to receive the message before disconnect" delay
- Should be a named constant

**Token resolution generates new UUID every launch** (`TheMuscle.swift:79-84`)
- WIRE-PROTOCOL.md states tokens are "persisted in UserDefaults and reused across app relaunches"
- Actual implementation: `UUID().uuidString` every time
- Documentation drift: tokens are ephemeral unless `INSIDEJOB_TOKEN` is set

**No unit tests for TheMuscle**
- Session locking logic (driver identity matching, force-takeover, timer behavior) is complex
- Could be tested with mock server/client without UIKit dependency
- The dual-timer interaction is particularly worth testing

### LOW PRIORITY

**Session connections tracked by client ID strings**
- `activeSessionConnections: Set<String>` stores client IDs
- Client IDs come from `SimpleSocketServer` connection tracking
- If IDs were reused (unlikely but possible), stale entries could accumulate
