# System Topology

The whole machine in one frame: an agent on the host drives the app through the wire, and everything that runs inside the app process is compiled out of release builds. This diagram answers "what talks to what, and where does each piece live?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md)
**Source of truth:** `ButtonHeist/Sources/TheScore/Messages.swift`, `ButtonHeist/Sources/TheScore/TLSPreSharedKeyMaterial.swift`, `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift`, `ButtonHeist/Sources/TheInsideJob/Server/SocketListenerStartup.swift`, `ButtonHeist/Sources/TheInsideJob/Server/BonjourAdvertisement.swift`, `ButtonHeistCLI/Package.swift`, `ButtonHeistMCP/Package.swift`

```mermaid
flowchart TD
    subgraph host["Host: macOS"]
        AGENT["Agent or test runner"]
        MCP["buttonheist-mcp<br/>26 MCP tools"]
        CLI["buttonheist CLI"]
        FENCE["TheFence<br/>command parse and dispatch"]
        HANDOFF["TheHandoff<br/>discovery and connection"]
        AGENT --> MCP
        AGENT --> CLI
        MCP --> FENCE
        CLI --> FENCE
        FENCE --> HANDOFF
    end

    subgraph app["iOS app process"]
        subgraph debug["#if DEBUG only"]
            LISTENER["NWListener<br/>Bonjour: _buttonheist._tcp"]
            MUSCLE["TheMuscle<br/>admission, auth, sessions"]
            CREW["Crew<br/>TheBrains · TheStash · TheSafecracker<br/>TheTripwire · TheBurglar · TheGetaway"]
            LISTENER --> MUSCLE
            MUSCLE --> CREW
        end
        AX["UIKit accessibility tree<br/>labels · values · traits · actions"]
        CREW -- "reads via parser<br/>acts via accessibilityActivate()" --> AX
    end

    HANDOFF -- "TLS-PSK wire · token auth<br/>exact buttonHeistVersion handshake" --> LISTENER
```

Notes:

- The wire is TLS with a pre-shared key derived from the session token (`ButtonHeistTLSPreSharedKey.makeNetworkParameters(token:)`, HKDF-SHA256, cipher `TLS_PSK_WITH_AES_128_GCM_SHA256`). Token auth then happens again at the message layer (`authenticate`).
- The version handshake compares the client's and server's `buttonHeistVersion` for exact equality and rejects on any mismatch (`MuscleHandshakePhase`).
- Everything inside the `#if DEBUG` border — the listener, TheMuscle, and the crew — does not exist in release builds. The accessibility tree is the surface the server reads and acts on; there is no other channel into the app.
