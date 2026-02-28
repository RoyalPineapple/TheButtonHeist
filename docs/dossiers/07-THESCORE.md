# TheScore - The Score

> **Module:** `ButtonHeist/Sources/TheScore/`
> **Platform:** iOS 17.0+ / macOS 14.0+ (cross-platform, no UIKit/AppKit)
> **Role:** Shared wire protocol definitions - the contract between iOS server and macOS clients

## Responsibilities

TheScore is the protocol bible. It defines:

1. **All client-to-server messages** (`ClientMessage` - 24 cases)
2. **All server-to-client messages** (`ServerMessage` - 13 cases)
3. **UI element types** (`HeistElement`, `Interface`, `ElementNode`, `ElementAction`)
4. **Action result types** (`ActionResult`, `InterfaceDelta`, `ActionMethod`)
5. **Media payloads** (`ScreenPayload`, `RecordingPayload`)
6. **Interaction events** (`InteractionEvent`) - wire-level command/result recording (NEW)
7. **Server info** (`ServerInfo`)
8. **Protocol constants** (service type, version)

## Architecture Diagram

```mermaid
graph TD
    subgraph TheScore["TheScore (Cross-Platform)"]
        Messages["Messages.swift - Constants: serviceType, protocolVersion"]
        Client["ClientMessages.swift - ClientMessage enum (24 cases)"]
        Server["ServerMessages.swift - ServerMessage enum (13 cases) - ActionResult, InterfaceDelta, - ScreenPayload, RecordingPayload"]
        Elements["Elements.swift - HeistElement, Interface, - ElementNode, ElementAction, - Group, HeistCustomContent"]
    end

    subgraph Consumers["Consumers"]
        TheInsideJob["TheInsideJob - (encodes ServerMessage, - decodes ClientMessage)"]
        Wheelman["Wheelman - (encodes ClientMessage, - decodes ServerMessage)"]
        ButtonHeist["ButtonHeist - (re-exports TheScore)"]
    end

    Messages --> TheInsideJob
    Messages --> Wheelman
    Client --> TheInsideJob
    Client --> Wheelman
    Server --> TheInsideJob
    Server --> Wheelman
    Elements --> TheInsideJob
    Elements --> Wheelman
    TheScore --> ButtonHeist
```

## Message Catalog

```mermaid
graph TD
    subgraph ClientMessages["ClientMessage (24 cases)"]
        Auth["authenticate(AuthenticatePayload)"]
        Sub["subscribe / unsubscribe"]
        Ping["ping"]
        Query["requestInterface / requestScreen / waitForIdle"]
        Actions["activate / increment / decrement - performCustomAction"]
        Touch["touchTap / touchLongPress / touchSwipe - touchDrag / touchPinch / touchRotate - twoFingerTap / touchDrawPath / touchDrawBezier"]
        Text["typeText / editAction / resignFirstResponder"]
        Recording["startRecording / stopRecording"]
    end

    subgraph ServerMessages["ServerMessage (13 cases)"]
        AuthResp["authRequired / authFailed / authApproved"]
        Info["info(ServerInfo)"]
        Data["interface(Interface) / screen(ScreenPayload)"]
        Pong["pong"]
        Error["error(String)"]
        Action["actionResult(ActionResult)"]
        Session["sessionLocked(String)"]
        Rec["recordingStarted / recording(RecordingPayload) / recordingError(String)"]
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
        +Int order
        +String description
        +String? label
        +String? value
        +String? identifier
        +String? hint
        +[String] traits
        +Frame frame
        +Point? activationPoint
        +Bool respondsToUserInteraction
        +[ElementAction] actions
        +[HeistCustomContent]? customContent
    }

    class ElementNode {
        <<enum>>
        element(order: Int)
        container(Group, [ElementNode])
    }

    class ElementAction {
        <<enum>>
        activate
        increment
        decrement
        custom(String)
    }

    class ActionResult {
        +Bool success
        +ActionMethod method
        +String? message
        +String? value
        +InterfaceDelta? interfaceDelta
        +Bool? animating
    }

    class InterfaceDelta {
        +DeltaKind kind
        +Int elementCount
        +[HeistElement]? addedElements
        +[Int]? removedOrders
        +[ValueChange]? valueChanges
        +Interface? newInterface
    }

    Interface --> HeistElement
    Interface --> ElementNode
    HeistElement --> ElementAction
    ActionResult --> InterfaceDelta

    class InteractionEvent {
        +Double timestamp
        +ClientMessage command
        +ActionResult result
        +Interface interfaceBefore
        +Interface interfaceAfter
    }

    InteractionEvent --> ActionResult
    InteractionEvent --> Interface
```

## Wire Protocol

- **Framing:** Newline-delimited JSON (each message is JSON + `0x0A`)
- **Protocol version:** `"3.1"` (token auth + session locking)
- **Service type:** `_buttonheist._tcp`
- **Encoding:** `Codable` with standard `JSONEncoder`/`JSONDecoder`
- **All types:** `Codable` + `Sendable` for Swift 6 concurrency (note: `ClientMessage` was made `Sendable` to support `InteractionEvent`)

## Items Flagged for Review

### MEDIUM PRIORITY

**`InteractionEvent` stores full Interface snapshots** (NEW - `ServerMessages.swift`)
- Each event includes `interfaceBefore` and `interfaceAfter` as full `Interface` objects
- These contain all `HeistElement` arrays, which can be large
- In a recording with many interactions, this could produce a substantial JSON payload
- No compression or deduplication between consecutive snapshots
- Well-tested though: `RecordingPayloadTests` covers round-trip, backward compat, and nil cases

**`ElementAction` custom Codable** (`Elements.swift:27-48`)
- Known actions encode as plain strings: `"activate"`, `"increment"`, `"decrement"`
- Custom actions encode as their name string directly
- Decoding: if the string isn't one of the known three, it's treated as `custom(name)`
- This means a custom action named `"activate"` would be decoded as the built-in `.activate`
- Edge case but worth noting

**`ActionMethod` has cases that may not round-trip cleanly through tests**
- `ActionCommandTests.swift:488-512` tests all `ActionMethod` cases but is missing 4:
  - `.typeText`, `.editAction`, `.resignFirstResponder`, `.waitForIdle`
- These cases exist in `ServerMessages.swift:214-233` but aren't in the test array

### LOW PRIORITY

**Protocol version is a string, not a numeric**
- `protocolVersion = "3.1"` - no formal version comparison logic exists
- Clients and servers don't negotiate or validate versions
- If a version mismatch occurs, messages may silently fail to decode

**No formal schema validation**
- Messages rely entirely on `Codable` for validation
- An invalid JSON field silently produces a decode error (caught by `try?` in receivers)
- No explicit schema version negotiation in the handshake
