# TheScore — The Score

> **Module:** `ButtonHeist/Sources/TheScore/`
> **Platform:** iOS 17.0+ / macOS 14.0+ (cross-platform, no UIKit/AppKit)
> **Role:** Shared wire protocol definitions — the contract between iOS server and macOS clients

## Responsibilities

TheScore is the shared playbook. It defines:

1. **All client-to-server messages** (`ClientMessage` — 33 cases)
2. **All server-to-client messages** (`ServerMessage` — 18 cases, including `status(StatusPayload)`)
3. **Request/response envelopes** (`RequestEnvelope`, `ResponseEnvelope`) for correlation
4. **UI element types** (`HeistElement`, `Interface`, `ElementNode`, `ElementAction`, `Group`, `HeistCustomContent`)
5. **Element matching** (`ElementMatcher`, `MatchScope`) — structured multi-field AND matching with scope filtering
6. **Action result types** (`ActionResult`, `InterfaceDelta`, `ActionMethod`, `ScrollSearchResult`)
7. **Action outcome signals** (`ActionExpectation`, `ExpectationResult`) — outcome classifiers for actions
8. **Media payloads** (`ScreenPayload`, `RecordingPayload`)
9. **Interaction events** (`InteractionEvent`) — wire-level command/result recording, also broadcast live to observers
10. **Status types** (`StatusPayload`, `StatusIdentity`, `StatusSession`) — server identity and session state
11. **Watch payload** (`WatchPayload`) — observer connection parameters
12. **Server info** (`ServerInfo`)
13. **Protocol constants** (service type, version)
14. **`ButtonHeistActor`** — dedicated global actor for the host-side control plane
15. **Connection scope types** (`ConnectionScope`) — configurable connection source filtering (simulator, USB, network) with address classification
16. **Unit-point geometry** (`UnitPoint`) — element-relative coordinates for gestures

## Source Files

| File | Contents |
|------|----------|
| `Messages.swift` | `buttonHeistServiceType`, `protocolVersion` ("6.4"), `WireMessageType` (50 cases), `ButtonHeistActor` |
| `ClientMessages.swift` | `RequestEnvelope`, `ClientMessage` (33 cases), all action target structs, `UnitPoint`, `RecordingConfig` |
| `ServerMessages.swift` | `ResponseEnvelope`, `ServerMessage` (18 cases), `ActionResult`, `InterfaceDelta`, `StatusPayload`, `ScreenPayload`, `RecordingPayload`, `InteractionEvent`, `ServerInfo` |
| `Elements.swift` | `HeistElement`, `Interface`, `ElementNode`, `Group`, `ElementAction`, `HeistCustomContent`, `ElementMatcher`, `MatchScope` |
| `ClientMessages+WireCoding.swift` | Custom flat envelope encoding for client messages |
| `ServerMessages+WireCoding.swift` | Custom flat envelope encoding for server messages |
| `ConnectionScope.swift` | `ConnectionScope` enum, `NetworkInterfaceNaming` protocol |

## Architecture Diagram

```mermaid
graph TD
    subgraph TheScore["TheScore (Cross-Platform)"]
        Messages["Messages.swift — serviceType, protocolVersion, WireMessageType (50 cases)"]
        Client["ClientMessages.swift — RequestEnvelope, ClientMessage (33 cases), UnitPoint"]
        Server["ServerMessages.swift — ResponseEnvelope, ServerMessage (18 cases), StatusPayload"]
        Elements["Elements.swift — HeistElement, Interface, ElementMatcher, MatchScope"]
        ConnScope["ConnectionScope.swift — ConnectionScope, NetworkInterfaceNaming"]
    end

    subgraph Consumers["Consumers"]
        TheInsideJob["TheInsideJob — encodes ServerMessage, decodes ClientMessage"]
        TH["TheHandoff / ButtonHeist — encodes ClientMessage, decodes ServerMessage"]
    end

    TheScore --> TheInsideJob
    TheScore --> TH
```

## Message Catalog

```mermaid
graph TD
    subgraph ClientMessages["ClientMessage (33 cases)"]
        Hello["clientHello"]
        Auth["authenticate(AuthenticatePayload)"]
        Sub["subscribe / unsubscribe"]
        Ping["ping / status"]
        Query["requestInterface / requestScreen / waitForIdle"]
        Actions["activate / increment / decrement / performCustomAction"]
        Touch["touchTap / touchLongPress / touchSwipe / touchDrag / touchPinch / touchRotate / touchTwoFingerTap / touchDrawPath / touchDrawBezier"]
        Scroll["scroll / scrollToVisible / scrollToEdge"]
        Text["typeText / editAction / resignFirstResponder"]
        Pasteboard["setPasteboard / getPasteboard"]
        Recording["startRecording / stopRecording"]
        Watch["watch(WatchPayload)"]
    end

    subgraph ServerMessages["ServerMessage (18 cases)"]
        HelloResp["serverHello / protocolMismatch"]
        AuthResp["authRequired / authFailed / authApproved"]
        Info["info(ServerInfo)"]
        Data["interface(Interface) / screen(ScreenPayload)"]
        Pong["pong"]
        Error["error(String)"]
        Action["actionResult(ActionResult)"]
        Session["sessionLocked(SessionLockedPayload)"]
        Rec["recordingStarted / recordingStopped / recording(RecordingPayload) / recordingError(String)"]
        Interaction["interaction(InteractionEvent)"]
        Status["status(StatusPayload)"]
    end
```

## Element Model

```mermaid
classDiagram
    class Interface {
        +Date timestamp
        +[HeistElement] elements
        +[ElementNode]? tree
    }

    class HeistElement {
        +String heistId
        +Int order
        +String description
        +String? label
        +String? value
        +String? identifier
        +String? hint
        +[String] traits
        +Double frameX
        +Double frameY
        +Double frameWidth
        +Double frameHeight
        +Double activationPointX
        +Double activationPointY
        +Bool respondsToUserInteraction
        +[ElementAction] actions
        +[HeistCustomContent]? customContent
        +frame: CGRect (computed)
        +activationPoint: CGPoint (computed)
    }

    class ElementNode {
        <<indirect enum>>
        element(order: Int)
        container(Group, [ElementNode])
    }

    class Group {
        +String type
        +String? label
        +String? value
        +String? identifier
        +Double frameX/Y/Width/Height
    }

    class ElementAction {
        <<enum>>
        activate
        increment
        decrement
        custom(String)
    }

    class HeistCustomContent {
        +String label
        +String value
        +Bool isImportant
    }

    Interface --> HeistElement
    Interface --> ElementNode
    ElementNode --> Group
    HeistElement --> ElementAction
    HeistElement --> HeistCustomContent
```

## Element Matching

```mermaid
classDiagram
    class ElementMatcher {
        +String? label
        +String? identifier
        +String? heistId
        +String? value
        +[String]? traits
        +[String]? excludeTraits
        +MatchScope? scope
        +Bool? absent
        +resolvedScope: MatchScope (computed)
        +isAbsent: Bool (computed)
    }

    class MatchScope {
        <<enum>>
        elements — leaves only (default)
        containers — container nodes only
        both — leaves and containers
    }

    ElementMatcher --> MatchScope
```

All specified fields must match (AND logic). `resolvedScope` defaults to `.elements` when nil. `isAbsent` defaults to `false` — when `true`, the match succeeds when no element is found.

## Action Results and Deltas

```mermaid
classDiagram
    class ActionResult {
        +Bool success
        +ActionMethod method
        +String? message
        +String? value
        +InterfaceDelta? interfaceDelta
        +Bool? animating
        +String? elementLabel
        +String? elementValue
        +[String]? elementTraits
        +String? screenName
        +ScrollSearchResult? scrollSearchResult
    }

    class InterfaceDelta {
        +DeltaKind kind
        +Int elementCount
        +[HeistElement]? added
        +[String]? removed
        +[ElementUpdate]? updated
        +Interface? newInterface
    }

    class DeltaKind {
        <<enum>>
        noChange
        elementsChanged
        screenChanged
    }

    class ScrollSearchResult {
        +Int scrollCount
        +Int uniqueElementsSeen
        +Int? totalItems
        +Bool exhaustive
        +HeistElement? foundElement
    }

    class ElementUpdate {
        +String heistId
        +[PropertyChange] changes
    }

    class PropertyChange {
        +ElementProperty property
        +String? old
        +String? new
    }

    class ElementProperty {
        <<enum>>
        label / value / traits / hint / actions / frame / activationPoint
        +isGeometry: Bool (computed)
    }

    ActionResult --> InterfaceDelta
    ActionResult --> ScrollSearchResult
    InterfaceDelta --> DeltaKind
    InterfaceDelta --> ElementUpdate
    ElementUpdate --> PropertyChange
    PropertyChange --> ElementProperty
```

## Status Types

```mermaid
classDiagram
    class StatusPayload {
        +StatusIdentity identity
        +StatusSession session
    }

    class StatusIdentity {
        +String appName
        +String bundleIdentifier
        +String appBuild
        +String deviceName
        +String systemVersion
        +String buttonHeistVersion
    }

    class StatusSession {
        +Bool active
        +Bool watchersAllowed
        +Int activeConnections
    }

    StatusPayload --> StatusIdentity
    StatusPayload --> StatusSession
```

`status` is allowed on the pre-auth path for any client that has completed the `clientHello` → `serverHello` handshake.

## Outcome Signals

```mermaid
classDiagram
    class ActionExpectation {
        <<enum>>
        screenChanged
        elementsChanged
        elementUpdated(heistId?, property?, oldValue?, newValue?)
        +validate(against: ActionResult) ExpectationResult
        +validateDelivery(ActionResult)$ ExpectationResult
    }

    class ExpectationResult {
        +Bool met
        +ActionExpectation? expectation
        +String? actual
    }

    ActionExpectation --> ExpectationResult
```

## Gesture Targets with UnitPoint

`UnitPoint` enables element-relative coordinate specification. Origin `(0,0)` = top-left, `(1,1)` = bottom-right, `(0.5,0.5)` = center. Values outside 0–1 extend beyond the element's frame.

`SwipeTarget` supports three resolution paths:
1. **Unit-point pair**: `start` + `end` as `UnitPoint` relative to element frame
2. **Direction-to-unit-point**: `direction` expands to `defaultStart`/`defaultEnd` unit points
3. **Absolute coordinates**: `startX/Y` + `endX/Y` screen points (legacy)

## Wire Protocol

- **Framing:** Newline-delimited JSON (each message is JSON + `0x0A`)
- **Protocol version:** `"6.4"` (explicit `type` / `payload` envelopes + exact hello/version matching)
- **Service type:** `_buttonheist._tcp`
- **Encoding:** `Codable` with custom top-level envelope coding at the wire boundary
- **All types:** `Codable` + `Sendable` for Swift 6 concurrency

## Action Method Catalog

`ActionMethod` (23 cases): `activate`, `increment`, `decrement`, `syntheticTap`, `syntheticLongPress`, `syntheticSwipe`, `syntheticDrag`, `syntheticPinch`, `syntheticRotate`, `syntheticTwoFingerTap`, `syntheticDrawPath`, `typeText`, `customAction`, `editAction`, `resignFirstResponder`, `setPasteboard`, `getPasteboard`, `waitForIdle`, `scroll`, `scrollToVisible`, `scrollToEdge`, `elementNotFound`, `elementDeallocated`

## Items Flagged for Review

### MEDIUM PRIORITY

**`ElementAction` custom Codable** (`Elements.swift:27-60`)
- Known actions encode as plain strings: `"activate"`, `"increment"`, `"decrement"`
- Custom actions encode as `{"custom":"name"}` objects
- Decoding: tries `{"custom":"name"}` keyed form first, falls back to plain string
- A plain string that isn't one of the known three is treated as `.custom(name)` for backward compatibility

### LOW PRIORITY

**Nested tree encoding still exposes Swift synthesized shape**
- Top-level request/response envelopes are now explicit `type` / `payload`
- `ElementNode.container` still encodes as `{"container":{"_0":Group,"children":[...]}}`
- Accurate, but awkward compared to the rest of the wire model

**No formal schema validation**
- Messages rely entirely on `Codable` for validation
- An invalid JSON field silently produces a decode error (caught by `try?` in receivers)
- Exact protocol matching now happens during `serverHello` / `clientHello`
