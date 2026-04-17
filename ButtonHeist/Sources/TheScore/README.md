# TheScore

Shared wire protocol. Every type that crosses the TCP boundary lives here. No UIKit, no AppKit, no behavior — pure type definitions and Codable conformances.

## Reading order

1. **`Messages.swift`** — Start here. `WireMessageType` is a 54-case `String` enum — every JSON message has a `"type"` key whose value is one of these raw strings. Also defines `TXTRecordKey` (Bonjour record keys), `EnvironmentKey` (all env vars in one place), and the protocol/product version constants.

2. **`Elements.swift`** — The element model. Nearly everything else references these types.
   - `HeistElement` — wire representation of one accessibility element (heistId, label, value, traits, frame, actions, etc.)
   - `HeistTrait` — 48 named cases plus `.unknown(String)` for forward compatibility. Any unrecognized trait string round-trips correctly.
   - `ElementMatcher` — search predicate: label, identifier, value, traits, excludeTraits. All optional, AND semantics, case-insensitive substring matching.
   - `ElementTarget` — two cases: `.heistId(String)` for exact lookup, `.matcher(ElementMatcher, ordinal: Int?)` for predicate search. Wire format is flat — matcher fields sit at the same JSON level as heistId, no nesting.
   - `Interface` — timestamp + `[HeistElement]` + optional `[ElementNode]` tree. Computed properties derive `screenName`, `screenId`, and `navigation` context from the element list.
   - `ElementAction` — four cases with dual encoding: built-in actions are bare strings, `.custom(String)` is `{"custom": "name"}`.

3. **`ClientMessages.swift`** — What clients send. `RequestEnvelope` wraps `protocolVersion`, `requestId`, and a `ClientMessage` (37 cases). Each action case carries a typed target struct (`TouchTapTarget`, `SwipeTarget`, `ScrollTarget`, etc.). `RecordingConfig` validates fps/scale ranges during deserialization, not after.

4. **`ServerMessages.swift`** — What the server sends back. `ResponseEnvelope` adds `backgroundDelta: InterfaceDelta?` — UI changes that happened while the client was processing the previous response (lives on the envelope, not inside `ServerMessage`, because any response type can carry it).
   - `ActionResult` — the richest payload: success/failure, method, message, value, interfaceDelta, element metadata, scroll/explore results.
   - `InterfaceDelta` — `.noChange`, `.elementsChanged` (with added/removed/updated lists), or `.screenChanged` (with full new `Interface`).
   - `ActionExpectation` — recursive enum for outcome classification. `.elementsChanged` is treated as a subset of `.screenChanged` in validation.

5. **`ClientMessages+WireCoding.swift`** / **`ServerMessages+WireCoding.swift`** — Hand-written Codable for the envelope types. Both use `container.superDecoder(forKey: .payload)` to scope payload decoding — each message type's `init(from:)` sees the `payload` object as its root. Three-group dispatch chains (`decodeProtocolMessage` → `decodeActionMessage` → `decodeTouchMessage` → etc.) with early return.

6. **`ConnectionScope.swift`** — Three-case enum: `.simulator`, `.usb`, `.network`. Default is `[.simulator, .usb]` — network is opt-in.

7. **`HeistPlayback.swift`** — Recording/replay format. `HeistEvidence` uses a two-pass Codable: first pass reads known fields via typed `CodingKeys`, second pass reads all remaining keys via `DynamicCodingKey` into the `arguments` dictionary. The wire format is intentionally flat so `toRequestDictionary()` can construct a valid TheFence request without translation.

## How a message round-trips

**Client encodes:** `RequestEnvelope(message: .activate(.heistId("button_save")))` → encoder writes `{"protocolVersion":"6.8","type":"activate","payload":{"heistId":"button_save"}}`. The `type` string comes from `ClientMessage.wireMessageType`.

**Server decodes:** `RequestEnvelope.decoded(from: data)` → reads `type` as `WireMessageType.activate` → `decodeActionMessage` calls `ElementTarget(from: payloadDecoder)` → returns `.activate(.heistId("button_save"))`.

**Server encodes response:** `ResponseEnvelope(message: .actionResult(...), backgroundDelta: nil)` → encoder writes the envelope with `type: "actionResult"` and the result as `payload`.

**Client decodes:** `ResponseEnvelope(from: data)` → reads `type`, `backgroundDelta`, payload decoder → `decodeStateMessage` matches `.actionResult` → synthesized Codable on `ActionResult`.

> Full dossier: [`docs/dossiers/18-THESCORE.md`](../../../docs/dossiers/18-THESCORE.md)
