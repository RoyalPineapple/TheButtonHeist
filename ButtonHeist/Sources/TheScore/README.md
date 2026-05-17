# TheScore

Shared wire protocol. Every type that crosses the TCP boundary lives here. No UIKit, no AppKit, no behavior — pure type definitions and Codable conformances.

## Reading order

1. **`Messages.swift`** — Start here. `WireMessageType` is a 54-case `String` enum — every JSON message has a `"type"` key whose value is one of these raw strings. Also defines `TXTRecordKey` (Bonjour record keys), `EnvironmentKey` (all env vars in one place), and `buttonHeistVersion` — the single product version checked for exact equality at handshake time.

2. **`Elements.swift`** — The element model. Nearly everything else references these types.
   - `HeistElement` — wire representation of one accessibility element (heistId, label, value, traits, frame, actions, etc.)
   - `HeistTrait` — 43 named cases plus `.unknown(String)` for forward compatibility. Any unrecognized trait string round-trips correctly.
   - `ElementMatcher` — search predicate: label, identifier, value, traits, excludeTraits. All optional, AND semantics, case-insensitive equality with typography folding (smart quotes/dashes/ellipsis fold to ASCII; emoji/accents/CJK pass through). Matching is exact or miss — no substring fallback in resolution. The static helpers `ElementMatcher.stringEquals` / `ElementMatcher.stringContains` are the shared comparison primitives used by both `HeistElement.matches` (client) and `AccessibilityElement.matches` (server) so the same input produces the same outcome on both sides.
   - `ElementTarget` — two cases: `.heistId(String)` for exact lookup, `.matcher(ElementMatcher, ordinal: Int?)` for predicate search. Wire format is flat — matcher fields sit at the same JSON level as heistId, no nesting.
   - `Interface` — timestamp + canonical `[InterfaceNode]` tree. Computed properties derive the flat element list, `screenName`, `screenId`, and `navigation` context from that tree.
   - `ElementAction` — four cases with dual encoding: built-in actions are bare strings, `.custom(String)` is `{"custom": "name"}`.

3. **`ClientMessages.swift`** — What clients send. `RequestEnvelope` wraps `buttonHeistVersion`, `requestId`, and a `ClientMessage` (37 cases). Each action case carries a typed target struct (`TouchTapTarget`, `SwipeTarget`, `ScrollTarget`, etc.). `RecordingConfig` validates fps/scale ranges during deserialization, not after.

4. **`ServerMessages.swift`** — What the server sends back. `ResponseEnvelope` carries `accessibilityTrace: AccessibilityTrace?` as the source-of-truth accessibility record for UI changes observed while the client was processing the previous response. Background deltas are not stored on the envelope; clients derive compact views from the trace at formatting or expectation edges.
   - `ActionResult` — the richest payload: success/failure, method, message, value, accessibilityDelta, element metadata, scroll/explore results.
   - `AccessibilityTrace` — a linear chain of full `AccessibilityTrace.Capture` values. Each capture owns a content hash and points to the previous capture hash; deltas, summaries, and recording receipts derive from the chain.
   - `AccessibilityTrace.Delta` — derived compact view: `.noChange`, `.elementsChanged` (with added/removed/updated lists), or `.screenChanged` (with full new `Interface`).
   - `ActionExpectation` — recursive enum for outcome classification. `.elementsChanged` is treated as a subset of `.screenChanged` in validation.

5. **`ClientMessages+WireCoding.swift`** / **`ServerMessages+WireCoding.swift`** — Hand-written Codable for the envelope types. Both use `container.superDecoder(forKey: .payload)` to scope payload decoding — each message type's `init(from:)` sees the `payload` object as its root. Three-group dispatch chains (`decodeProtocolMessage` → `decodeActionMessage` → `decodeTouchMessage` → etc.) with early return.

6. **`ConnectionScope.swift`** — Three-case enum: `.simulator`, `.usb`, `.network`. Default is `[.simulator, .usb]` — network is opt-in.

7. **`HeistPlayback.swift`** — `.heist` persistence format. `HeistEvidence` uses a two-pass Codable: first pass reads known fields via typed `CodingKeys`, second pass reads all remaining keys via `DynamicCodingKey` into the `arguments` dictionary. The wire format is intentionally flat for compatibility at the file edge; runtime playback binds the decoded evidence to typed `TheFence.Command` operations before execution. `_recorded` may carry accessibility traces, deltas, and expectation receipts for diagnostics; playback ignores them. Recording uses those trace captures when available to derive the smallest stable matcher for the recorded element.

## How a message round-trips

**Client encodes:** `RequestEnvelope(message: .activate(.heistId("button_save")))` → encoder writes `{"buttonHeistVersion":"<calver>","type":"activate","payload":{"heistId":"button_save"}}`. The `type` string comes from `ClientMessage.wireRepresentation`.

**Server decodes:** `RequestEnvelope.decoded(from: data)` → reads `type` as `WireMessageType.activate` → `decodeActionMessage` calls `ElementTarget(from: payloadDecoder)` → returns `.activate(.heistId("button_save"))`.

**Server encodes response:** `ResponseEnvelope(message: .actionResult(...), accessibilityTrace: trace)` → encoder writes the envelope with `type: "actionResult"`, the result as `payload`, and optional `accessibilityTrace` captures.

**Client decodes:** `ResponseEnvelope(from: data)` → reads `type`, optional `accessibilityTrace`, payload decoder → `decodeStateMessage` matches `.actionResult` → synthesized Codable on `ActionResult`.

> Full dossier: [`docs/dossiers/18-THESCORE.md`](../../../docs/dossiers/18-THESCORE.md)
