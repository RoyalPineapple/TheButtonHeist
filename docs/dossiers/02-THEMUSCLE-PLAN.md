# TheMuscle - Performance Improvement Plan

## Summary

Simplify session management to a single-session model with clear rules. Fix the token lifecycle bug. Add unit tests.

## Phase 1: Simplify to Single Session Model

**Goal:** Replace the dual-timer, multi-connection session tracking with a clean state machine.

### Session Rules (canonical):

**No active session:**
- New driver + valid token → allow in, becomes active driver
- New driver + no token → pop UI approval prompt
- New driver + invalid token → deny immediately

**Active session, same driver:**
- Valid token → allow in (rejoin session)
- Invalid token → deny
- No token → pop UI approval prompt

**Active session, different driver:**
- Any token (valid, invalid, or empty) → busy signal, NO UI prompt
- Busy signal includes: "Driver X is in control. Session will time out after 30s of inactivity."

**Session timeout:**
- 30 seconds without any interaction or heartbeat → session released
- Single timer, not dual. The lease timer concept is removed.

- [ ] **Remove `sessionReleaseTimer`** (disconnect timer) — only keep one inactivity/heartbeat timer
- [ ] **Remove `sessionLeaseTimer`** — replaced by the single timeout
- [ ] **Simplify `acquireSession` / `releaseSession`** to match the rules above
- [ ] **Remove `forceSession` flag** (no force-takeover; wait for timeout)
- [ ] **Build passes** after phase

### Files affected:
- `TheMuscle.swift` — rewrite session logic to match the state machine above

## Phase 2: Fix Token Lifecycle Bug

- [ ] **Remove `invalidateToken()` call from `releaseSession()`** — token has the same lifecycle as the app
- [ ] **Token only invalidated on explicit user action** (if ever), not on timer expiry
- [ ] **Build passes** after phase

### Files affected:
- `TheMuscle.swift` — remove `invalidateToken()` call from session release path

## Phase 3: Update Documentation

- [ ] **Update WIRE-PROTOCOL.md** — remove claim about UserDefaults persistence
- [ ] **Document that tokens are ephemeral** unless `INSIDEJOB_TOKEN` is set explicitly

### Files affected:
- `docs/WIRE-PROTOCOL.md`

## Phase 4: Fix Repeated Magic Numbers

- [ ] **Replace `100_000_000` with named constant:**
   ```swift
   private static let disconnectGracePeriod: UInt64 = 100_000_000  // 100ms
   ```
- [ ] **All three instances updated** (`TheMuscle.swift:125, 189, 249`)

### Files affected:
- `TheMuscle.swift`

## Phase 5: Add Unit Tests

- [ ] **Auth flow tests:** valid token → authenticated, invalid → rejected, empty → pending
- [ ] **Session rules tests:** no session + valid → acquired, same driver → allowed, different driver → busy, timeout after 30s
- [ ] **Token lifecycle tests:** token survives session release, stable across multiple cycles
- [ ] **Tests pass**

### Files:
- New: `ButtonHeist/Tests/InsideJobTests/TheMuscleTests.swift`

## Phase 6: Adopt Client Subscriptions (from InsideJob extraction)

- [ ] **Receive `subscribedClients: Set<String>`** from InsideJob
- [ ] **Receive subscribe/unsubscribe handling**
- [ ] **Receive `broadcastToSubscribed` helper**
- [ ] **Build passes** after phase

## Phase 7: UI Approval Discussion

No changes needed. Future considerations:
- Could show connecting client's IP in the prompt
- Could rate-limit approval prompts

## Phase 8: Client ID Tracking

Consider using a lightweight struct for type safety:
```swift
struct ClientIdentity: Hashable {
    let connectionId: String
    let driverId: String?
}
```

Low priority — only if it simplifies the code.

## Verification

- [ ] Dual timer system removed — single 30-second inactivity timer only
- [ ] `invalidateToken()` not called from session release
- [ ] WIRE-PROTOCOL.md updated for token behavior
- [ ] Magic `100_000_000` replaced with named constant
- [ ] Unit tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJobTests -destination 'platform=iOS Simulator,name=iPhone 16' test`
- [ ] No `swiftlint:disable` in TheMuscle.swift
