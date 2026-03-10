# Strategic Analysis Report: ButtonHeist Holistic Review

> Generated: 2026-03-10 | Commit: 1693db0 | Branch: RoyalPineapple/tallinn-v1

---

## Executive Summary

Button Heist is a well-architected iOS UI automation system at version 0.0.1 (~18.6K LOC across 8 modules, 158 tests). The codebase demonstrates strong architectural fundamentals -- clean layering, strict concurrency with Swift 6.0, a unified command dispatch pattern, and thoughtful separation of concerns via the heist crew metaphor. However, being early-stage, it has significant gaps in automated CI/CD, test coverage for the iOS server layer, security hardening for network-exposed surfaces, and performance observability.

**Key Strategic Insights:**

1. **Architecture is ahead of its maturity stage.** The 6-layer design with TheScore as a zero-dependency shared protocol is textbook clean architecture. The dual-client pattern (CLI + MCP over TheFence) is well-executed. This foundation will scale.

2. **Security posture requires immediate attention.** A TCP server with no TLS, plaintext token auth, and IOKit private API usage creates a non-trivial attack surface on any network. The `#if DEBUG` guard is the primary safety net.

3. **Test coverage is structurally uneven.** TheScore (protocol layer) and TheButtonHeist (client) have good coverage. TheInsideJob (the largest module at 4,324 LOC) has only 362 LOC of tests covering TheMuscle auth and bezier sampling -- zero tests for TheSafecracker, TheBagman, TheStakeout, or TheInsideJob command routing.

4. **No CI/CD pipeline exists.** GitHub Actions is unavailable (private repo without runners). The pre-commit checklist and `-warnings-as-errors` build policy are the current quality gates. This is acceptable at the current team size but should be revisited when runners become available.

5. **The MCP surface is the highest-leverage growth vector.** AI agent integration is the product's differentiator. The MCP server at 454 LOC with 14 tools is lean but could benefit from richer error context, streaming responses, and better observability for agent debugging.

**Top 3 Recommendations:**

| # | Recommendation | Impact | Effort | ROI |
|---|---------------|--------|--------|-----|
| 1 | Add TLS support to wire protocol | Secures token auth, enables production-adjacent use | 1-2 weeks | Eliminates top security risk |
| 2 | Instrument TheInsideJob with structured metrics | Enables performance optimization, debugging | 3-5 days | Unlocks data-driven decisions |
| 3 | Increase TheInsideJob unit test coverage | Protects interaction pipeline from regressions | 1-2 weeks | Catches bugs early |

*Note: CI/CD pipeline deferred — private repo without GitHub Actions runners. The `-warnings-as-errors` build policy and pre-commit checklist serve as current quality gates.*

---

## Detailed Findings

### Finding 1: Plaintext TCP with Token Auth

- **Problem**: The wire protocol runs over unencrypted TCP. Auth tokens are sent in plaintext JSON. On WiFi networks, any device on the same network can sniff tokens and impersonate clients.
- **Root Cause**: Design choice for simplicity at v0.0.1. The `#if DEBUG` compile guard limits exposure, but DEBUG builds are routinely deployed to shared test devices and simulators.
- **Impact**: Token interception allows unauthorized UI automation of any app running TheInsideJob. The 30 msg/s rate limit and max-5 connections provide some DoS protection, but do not address confidentiality.
- **Evidence**: `SimpleSocketServer.swift` uses `NWParameters.tcp` with no TLS configuration. `TheMuscle.swift` compares tokens via `payload.token == authToken` over the plaintext channel. The Bonjour advertisement (`_buttonheist._tcp`) makes discovery trivial.

### Finding 2: TheInsideJob Test Coverage Gap

- **Problem**: TheInsideJob is the largest module (4,324 LOC, 16 files) but has only 2 test files totaling 362 LOC -- covering only TheMuscle (auth/sessions) and bezier sampling. Zero coverage for TheSafecracker (touch injection), TheBagman (element cache/delta), TheStakeout (recording), and TheInsideJob command routing.
- **Root Cause**: iOS server components require a running UIKit environment, making them harder to unit test. The CLI-first feedback loop has been the de facto testing strategy.
- **Impact**: Regressions in the interaction pipeline (refresh -> snapshot -> execute -> delta -> respond) can only be caught by end-to-end testing. TheBagman's delta computation logic is particularly testable but untested.
- **Evidence**: `ButtonHeist/Tests/TheInsideJobTests/` contains only `TheMuscleTests.swift` (277 LOC) and `BezierSamplerTests.swift` (85 LOC). TheSafecracker at ~1,500 LOC has zero test coverage.

### Finding 3: Singleton Pattern with Thread Safety Concerns

- **Problem**: `TheInsideJob.shared` uses `nonisolated(unsafe)` for the singleton storage (`_shared`). While `@MainActor` isolation protects most access, the `configure()` and `shared` accessors have a theoretical race window -- two threads could both see `_shared == nil` and create duplicate instances.
- **Root Cause**: Bridging between ObjC `+load` (ThePlant, which runs before Swift) and Swift's `@MainActor` isolation requires `nonisolated(unsafe)`.
- **Impact**: Low in practice (ThePlant calls configure() on a single thread during load), but the pattern is fragile. A future caller from a background thread could trigger the race.
- **Evidence**: Lines 21-38 of `TheInsideJob.swift` -- `nonisolated(unsafe) private static var _shared` with no synchronization primitive.

### Finding 4: TheFence Uses Untyped Dictionary API

- **Problem**: `TheFence.execute(request:)` accepts `[String: Any]` and manually extracts arguments via `stringArg()`, `intArg()`, `doubleArg()` helpers. This bypasses Swift's type system entirely and has no compile-time validation of command schemas.
- **Root Cause**: Designed to accept arbitrary JSON from CLI (ArgumentParser) and MCP (JSON-RPC) without requiring a shared typed request model.
- **Impact**: Typos in argument keys (e.g., `"identifer"` vs `"identifier"`) silently produce nil values. Error messages are generated at runtime rather than caught at compile time. The 29-command switch statement in `dispatch()` is a maintenance burden.
- **Evidence**: `TheFence.swift` lines 458-528 -- the dispatch method is a 70-line switch statement with string-matched command names. The `elementTarget()` helper silently returns nil on missing keys.

### Finding 5: Memory Pressure from Base64 Video/Screenshot Encoding

- **Problem**: Screenshots (PNG) and recordings (H.264/MP4) are base64-encoded inline in JSON responses. A 7MB recording becomes ~9.3MB base64, held entirely in memory during encoding, transmission, and decoding. The MCP server explicitly notes it "omits large video data from responses."
- **Root Cause**: The NDJSON wire protocol requires single-line JSON messages, making binary streaming incompatible with the current framing.
- **Impact**: For large recordings (up to 7MB file limit), peak memory usage spikes to ~30MB (original + base64 encoded + JSON wrapper + decoded on client). On memory-constrained devices or when multiple recordings are in flight, this could trigger jetsam.
- **Evidence**: `TheStakeout` has a 7MB file size limit. `TheFence.handleStopRecording()` receives the full base64 payload. `RecordingPayload.videoData` is a `String` containing the entire base64 blob.

### Finding 6: Polling-Based Architecture for UI Hierarchy

- **Problem**: The accessibility hierarchy is polled at a configurable interval (default 1s) with a 300ms debounce on notification-triggered updates. This creates a tradeoff between responsiveness and CPU usage.
- **Root Cause**: UIKit's accessibility notifications are not comprehensive -- not all UI changes generate accessibility notifications, necessitating polling as a fallback.
- **Impact**: At 1s polling, rapid UI changes (animations, scrolling) may not be captured between polls. Reducing the interval increases CPU load from AccessibilityHierarchyParser. The hash comparison on every poll is O(n) in element count.
- **Evidence**: `TheInsideJob.swift` defines `defaultPollingInterval = 1_000_000_000` (1s) and `debounceInterval = 300_000_000` (300ms). `TheBagman` refreshes and hashes the full hierarchy on each poll.

---

## Strategic Recommendations

### Recommendation REC-001: Add TLS Support to Wire Protocol

- **Category**: Security
- **Priority**: Critical
- **Effort**: 1-2 weeks

**Impact Analysis:**
- Encrypts auth tokens in transit (currently plaintext)
- Protects against network-level sniffing of UI hierarchy data and screenshots
- Enables potential use beyond local development (e.g., remote device farms)
- Prerequisite for any compliance or enterprise adoption

**Implementation Plan:**

Phase 1 (Days 1-3): TLS for SimpleSocketServer
- Add `NWProtocolTLS.Options` to `NWParameters` in `SimpleSocketServer.startAsync()`
- Generate self-signed certificate at runtime (per-session)
- Pin certificate fingerprint in Bonjour TXT record for client verification
- Add `useTLS` configuration flag (default: true for WiFi, optional for loopback/USB)

Phase 2 (Days 4-7): Client-side TLS
- Update `DeviceConnection` to use TLS parameters
- Implement certificate pinning using TXT record fingerprint
- Handle TLS handshake failures gracefully (fall back to plaintext on loopback only)

Phase 3 (Days 8-10): Testing and documentation
- Add TLS negotiation tests
- Update `docs/WIRE-PROTOCOL.md` and `docs/AUTH.md`
- Bump protocol version to v5.0

**Risk Assessment:**
- Risk: Self-signed certificates cause trust errors on some network configurations
- Mitigation: Use loopback exemption for simulator builds; document certificate trust for physical devices
- Risk: TLS adds latency to connection establishment
- Mitigation: Network.framework TLS handshake is ~50ms on local network; negligible vs. 30s connection timeout

**Success Criteria:**
- All WiFi connections use TLS by default
- Token sniffing via `tcpdump` shows encrypted traffic only
- No regression in connection time (< 100ms increase acceptable)

**ROI**: High. TLS removes the single largest security concern. Network.framework's built-in TLS support means most of the work is configuration, not implementation.

---

### Recommendation REC-002: Instrument TheInsideJob with Structured Performance Metrics

- **Category**: Performance / Observability
- **Priority**: High
- **Effort**: 3-5 days

**Impact Analysis:**
- Provides data on hierarchy parse time, element count, delta computation cost, and action latency
- Enables data-driven decisions about polling interval, debounce timing, and memory management
- Supports debugging performance issues in agent workflows (where the human cannot observe)
- Addresses the TBD in the knowledge base: "Performance characteristics under load"

**Implementation Plan:**

Phase 1 (Days 1-2): Add signpost-based instrumentation
- Use `OSSignpost` for hierarchy parse, delta computation, action execution, and screenshot capture
- Add timing to `performInteraction()` pipeline stages
- Track element count per refresh and broadcast size in bytes

Phase 2 (Days 3-4): Expose metrics via wire protocol
- Add optional `ServerMetrics` payload to `ServerInfo` updates
- Include: avg parse time, element count, broadcast frequency, memory usage, active connection count
- Add `get_metrics` command to TheFence/CLI/MCP

Phase 3 (Day 5): Dashboard and alerting
- Log metrics via `os.log` with `.info` level for Instruments correlation
- Add CLI `buttonheist metrics` command for real-time monitoring
- Document performance baselines in `docs/ARCHITECTURE.md`

**Risk Assessment:**
- Risk: Instrumentation overhead affects performance
- Mitigation: OSSignpost is designed for production use; disabled when not profiling. Logging is `.info` level (filtered in release).
- Risk: Metrics add message payload size
- Mitigation: Metrics are optional and only sent on explicit request or at low frequency (every 10s max).

**Success Criteria:**
- Can answer: "How long does hierarchy parsing take for N elements?"
- Can answer: "What is the 95th percentile action latency?"
- Instruments traces show clear signpost intervals for each pipeline stage

**ROI**: High. Performance data eliminates guesswork for all future optimization decisions. Estimated 3 days of effort saves weeks of ad-hoc profiling over the project lifetime.

---

### Recommendation REC-003: Increase TheInsideJob Unit Test Coverage

- **Category**: Quality
- **Priority**: High
- **Effort**: 1-2 weeks

**Impact Analysis:**
- TheBagman delta computation is pure logic (no UIKit dependency) and highly testable -- currently 0 tests
- TheSafecracker action resolution logic can be tested with mock elements
- Raises test coverage from ~21% of LOC (3,391 / 15,988 application LOC) to estimated 35%+
- Reduces reliance on end-to-end testing for catching regressions

**Implementation Plan:**

Phase 1 (Days 1-3): TheBagman unit tests
- Test `InterfaceDelta` computation: noChange, valuesChanged, elementsChanged, screenChanged
- Test element hashing consistency
- Test snapshot/restore with mock accessibility data
- Target: 15-20 test cases, ~400 LOC

Phase 2 (Days 4-7): TheInsideJob command routing tests
- Test `handleClientMessage` routing for all 29 message types
- Test observer mode restrictions (read-only enforcement)
- Test error handling for malformed messages
- Target: 20-25 test cases, ~500 LOC

Phase 3 (Days 8-10): TheSafecracker action resolution tests
- Test activation-first pattern (accessibility activate -> synthetic tap fallback)
- Test element target resolution (by identifier, by order)
- Test input validation (max points, max segments)
- Target: 10-15 test cases, ~300 LOC

**Risk Assessment:**
- Risk: iOS-specific components require UIKit test host
- Mitigation: TheInsideJobTests already runs on iOS Simulator destination; infrastructure exists
- Risk: Mocking accessibility hierarchy for TheBagman tests is complex
- Mitigation: Create a `MockAccessibilityData` helper that generates test `HeistElement` arrays

**Success Criteria:**
- TheBagman delta logic: 100% branch coverage
- TheInsideJob routing: All 29 message types have at least one test
- Zero test failures on main branch (enforced by CI from REC-001)

**ROI**: High. TheBagman delta tests alone would have caught the class of bugs most likely to appear during protocol evolution. 1-2 weeks of effort protects the entire interaction pipeline.

---

### Recommendation REC-004: Introduce Typed Command Request Model

- **Category**: Code Quality / Maintainability
- **Priority**: Medium
- **Effort**: 1-2 weeks

**Impact Analysis:**
- Replaces the `[String: Any]` dictionary API in TheFence with a `CommandRequest` enum
- Enables compile-time validation of command arguments
- Eliminates the 70-line dispatch switch statement
- Makes CLI and MCP argument mapping explicit rather than implicit

**Implementation Plan:**

Phase 1 (Days 1-3): Define `CommandRequest` enum
- One case per command with typed associated values
- `CommandRequest.activate(target: ActionTarget)`
- `CommandRequest.typeText(text: String?, deleteCount: Int?, target: ActionTarget?)`
- Factory methods: `CommandRequest(from: [String: Any])` for backward compatibility

Phase 2 (Days 4-7): Refactor TheFence to use CommandRequest
- Replace `dispatch(command:args:)` with `dispatch(_ request: CommandRequest)`
- Keep `execute(request: [String: Any])` as a convenience that constructs CommandRequest
- CLI and MCP can construct CommandRequest directly, bypassing dictionary intermediary

Phase 3 (Days 8-10): Update CLI and MCP
- CLI commands construct `CommandRequest` directly from ArgumentParser options
- MCP tools construct `CommandRequest` directly from tool arguments
- Remove `stringArg()`, `intArg()`, `doubleArg()` helpers

**Risk Assessment:**
- Risk: Breaking change to TheFence public API
- Mitigation: Keep `execute(request: [String: Any])` as a deprecated convenience
- Risk: Large diff touching CLI, MCP, and TheFence simultaneously
- Mitigation: Phase 1 is additive (new type only); Phase 2-3 can be done incrementally per command

**Success Criteria:**
- Zero runtime `nil` from missing dictionary keys -- all argument validation happens at type construction
- TheFence `dispatch()` method is < 30 lines (delegating to typed handlers)
- CLI and MCP both bypass the dictionary intermediary

**ROI**: Medium-term. Initial investment is moderate, but the reduction in runtime errors and maintenance burden compounds as commands are added. Current 29 commands will likely grow to 40+ as gestures and features expand.

---

### Recommendation REC-005: Add Binary Streaming for Large Payloads

- **Category**: Performance / Scalability
- **Priority**: Medium
- **Effort**: 2-3 weeks

**Impact Analysis:**
- Eliminates ~33% base64 overhead for screenshots and recordings
- Reduces peak memory usage from ~4x payload to ~1x (streaming vs. buffering)
- Enables recordings larger than 7MB without memory pressure
- Prerequisite for video streaming or real-time screen mirroring features

**Implementation Plan:**

Phase 1 (Days 1-5): Design binary framing protocol
- Add a binary message type alongside NDJSON: `[4-byte length][payload]` with a type prefix byte
- JSON messages: `0x4A` prefix + NDJSON (backward compatible)
- Binary messages: `0x42` prefix + 4-byte length + raw bytes
- Response correlation: binary responses reference the original requestId via a header

Phase 2 (Days 6-10): Implement server-side streaming
- TheStakeout writes recording data to a temp file instead of memory
- On stop_recording, stream file contents in chunks via binary framing
- Screenshot streaming: send PNG data directly without base64 encoding

Phase 3 (Days 11-15): Client-side streaming + backward compat
- DeviceConnection handles both JSON and binary frames
- TheFence writes received binary data directly to output file
- Maintain base64 fallback for clients that cannot handle binary framing
- Bump protocol version

**Risk Assessment:**
- Risk: Breaking backward compatibility with existing clients
- Mitigation: Auto-detect framing by first byte; legacy clients continue to work with JSON-only
- Risk: Complexity of mixed framing in SimpleSocketServer
- Mitigation: Extract framing logic into a `MessageFramer` protocol with JSON and Binary implementations

**Success Criteria:**
- Screenshot transfer time reduced by 30%+ (no base64 encode/decode overhead)
- Recording transfer supports files up to 50MB without memory warnings
- Existing CLI/MCP clients work without changes (backward compat)

**ROI**: Medium-to-high. The 33% bandwidth reduction and memory improvement matter most for recordings and high-frequency screenshot use cases. If screen mirroring is on the roadmap, this becomes a prerequisite.

---

### Recommendation REC-006: Improve MCP Agent Experience with Richer Context

- **Category**: Product / Growth
- **Priority**: Medium
- **Effort**: 1 week

**Impact Analysis:**
- MCP is the primary growth vector -- AI agents are the differentiating use case
- Current MCP tools return raw data without guidance on what to do next
- Adding contextual hints, suggested next actions, and error recovery guidance would improve agent success rates
- Supports the "delta-first" workflow already recommended in CLAUDE.md

**Implementation Plan:**

Phase 1 (Days 1-2): Enrich action result responses
- Add `suggestedNextActions` field to ActionResult responses in MCP
- After activate: suggest "get_interface to see updated state" or "wait_for_idle if animation expected"
- On error: include specific recovery steps ("element not found -- call get_interface to refresh")

Phase 2 (Days 3-4): Add `describe_interface` tool
- Summarize the interface in natural language: "3 buttons, 1 text field, 1 list with 12 items"
- Include actionable elements with their identifiers
- Optimized for agent token efficiency (compact vs. full element dump)

Phase 3 (Days 5-7): Streaming interface updates
- Add a `subscribe_updates` MCP tool that sends notifications on interface changes
- Enables agents to react to UI changes without polling `get_interface`
- Uses MCP notification mechanism

**Risk Assessment:**
- Risk: MCP SDK may not support server-initiated notifications
- Mitigation: Check MCP SDK 0.11.0 capabilities; fall back to polling with `wait_for_idle`
- Risk: Richer responses increase token consumption for agents
- Mitigation: Make enhancements opt-in via tool arguments (e.g., `verbose: true`)

**Success Criteria:**
- Agent success rate on common workflows improves (measure via ai-fuzzer)
- MCP tool responses include actionable context in all error cases
- `describe_interface` response fits in < 500 tokens for typical UIs

**ROI**: High leverage. Each improvement multiplies across every AI agent using Button Heist. The MCP surface is the product's moat.

---

## Trade-off Analysis

| Option | Cost Impact | Performance Impact | Complexity | Risk Level | Timeline | Recommendation |
|--------|-------------|-------------------|------------|------------|----------|----------------|
| REC-001: TLS Support | None | +50ms connection | Medium | Medium | 1-2 weeks | **Do first** |
| REC-002: Instrumentation | None | < 1% overhead | Low | Low | 3-5 days | **Do in parallel** |
| REC-003: Test Coverage | None | N/A | Medium | Low | 1-2 weeks | **Do second** |
| REC-004: Typed Commands | None | Negligible | Medium | Medium | 1-2 weeks | **Plan for v0.1** |
| REC-005: Binary Streaming | None | -33% bandwidth, -75% memory | High | Medium | 2-3 weeks | **Plan for v0.2** |
| REC-006: MCP Enrichment | None | Minimal | Low | Low | 1 week | **Do in parallel** |

*CI/CD deferred: Private repo without GitHub Actions runners. Current quality gates: `-warnings-as-errors` build policy + pre-commit checklist in CLAUDE.md. Revisit when runners become available.*

### Strategic Options Compared

**Option A: Quality-First (REC-002 + REC-003)**
- Focus: Establish engineering foundation before adding features
- Timeline: 2-3 weeks
- Outcome: Performance data, 35%+ test coverage
- Best for: Sustainable development velocity, reducing future debugging time

**Option B: Security-First (REC-001 + REC-002)**
- Focus: Address the most visible risk (plaintext TCP) + instrumentation
- Timeline: 2-3 weeks
- Outcome: Encrypted transport, performance visibility
- Best for: Scenarios involving shared networks, team environments, or compliance requirements

**Option C: Growth-First (REC-006 + REC-002)**
- Focus: Improve the MCP agent experience to accelerate adoption
- Timeline: 2-3 weeks
- Outcome: Better agent success rates, performance visibility
- Best for: Maximizing early adoption and user feedback

**Recommendation**: Option B (Security-First) for the immediate term, with REC-006 (MCP enrichment) done in parallel given its low effort and high leverage. Test coverage (REC-003) follows.

---

## Implementation Roadmap

### Immediate (This Week)

- **[REC-001]** Phase 1: TLS for SimpleSocketServer (server-side encryption)
- **[REC-002]** Add OSSignpost instrumentation to `performInteraction()` pipeline
- Start **[REC-006]** Phase 1: enrich MCP action result responses with context

### Short-term (Weeks 2-4)

- **[REC-001]** Phase 2-3: Client-side TLS and protocol version bump
- **[REC-003]** Phase 1-2: TheBagman delta tests and TheInsideJob routing tests
- Complete **[REC-006]** Phase 2-3: `describe_interface` tool and streaming updates
- **[REC-002]** Phase 2-3: Expose metrics via wire protocol and CLI

### Medium-term (Months 2-3)

- **[REC-003]** Phase 3: TheSafecracker action resolution tests
- **[REC-004]** Full implementation of typed CommandRequest model

### Long-term (Months 3-6)

- **[REC-005]** Binary streaming protocol design and implementation
- Evaluate singleton thread safety fix (minor)
- Performance optimization based on REC-002 metrics data
- CI/CD pipeline when GitHub runners become available

---

## Dependency Analysis

```
REC-001 (CI)
  |
  +---> REC-004 (Tests) -- tests are only valuable with CI enforcement
  |
  +---> REC-002 (TLS) -- CI validates TLS changes don't break builds
  |
  +---> REC-005 (Typed Commands) -- CI validates refactoring correctness

REC-003 (Instrumentation)
  |
  +---> REC-006 (Binary Streaming) -- metrics data informs payload optimization
  |
  +---> Performance tuning decisions (polling interval, debounce timing)

REC-007 (MCP Enrichment) -- independent, no dependencies
```

**Critical Path**: REC-001 is the foundation. All quality and security improvements depend on CI for validation. Start here.

**Independent Tracks**:
- REC-003 (instrumentation) and REC-007 (MCP enrichment) can proceed in parallel with everything else
- REC-006 (binary streaming) is independent but benefits from metrics data from REC-003

---

## Appendix: Additional Observations

### Architecture Strengths (Preserve These)

1. **Clean layering**: TheScore has zero dependencies. The dependency graph is strictly acyclic. This is rare and valuable -- protect it.
2. **Dual-client pattern**: CLI and MCP as thin wrappers over TheFence is elegant. CommandCatalog as single source of truth is well-designed.
3. **Swift 6.0 strict concurrency**: `@MainActor`, `@ButtonHeistActor`, actor-isolated `SimpleSocketServer` -- the project fully embraces structured concurrency. This eliminates entire classes of data races.
4. **Interaction pipeline**: The refresh -> snapshot -> execute -> delta -> respond pattern is consistent across all 20+ action commands. This consistency makes the system predictable.
5. **Heist crew metaphor**: Beyond naming novelty, each component genuinely maps to a single responsibility. TheBagman owns elements, TheSafecracker owns touch, TheMuscle owns auth. The metaphor enforces SRP.

### Technical Debt Items (Low Priority)

1. **nonisolated(unsafe) usage**: 4 instances across SimpleSocketServer and TheInsideJob. Each is documented with rationale, but they represent escape hatches from Swift's concurrency model. Monitor as Swift evolves.
2. **Semaphore bridge in SimpleSocketServer.start()**: The synchronous `start()` method uses `DispatchSemaphore` to bridge to async. This is acceptable for one-time startup but would be problematic if called repeatedly.
3. **Rate limiting implementation**: The timestamp-array approach in `isRateLimited()` allocates and filters an array per message. For 30 msg/s this is fine; at higher rates, a token bucket would be more efficient.
4. **FenceResponse manual JSON serialization**: The `jsonDict()` method manually constructs `[String: Any]` dictionaries instead of using Codable. This is a maintenance risk as the response types evolve.

### Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| IOKit private API breaks in future iOS | Medium | Critical | Monitor iOS betas; maintain KIF-style fallback paths |
| AccessibilitySnapshot upstream diverges | Low | Medium | Minimal delta on fork (2 commits); rebase strategy documented |
| MCP SDK breaking changes | Medium | Medium | Pin to 0.11.0+; SDK is pre-1.0 so expect churn |
| Memory pressure from large hierarchies | Low | Medium | REC-003 metrics will quantify; add element count limits if needed |
| Token brute-force on WiFi | Low | High | REC-002 (TLS) eliminates; rate limiting provides interim protection |
