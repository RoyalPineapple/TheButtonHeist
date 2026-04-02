# Button Heist Crew Dossiers - Overview

## The Heist Metaphor

Button Heist is a remote iOS UI automation system structured as a heist crew. An iOS framework (TheInsideJob) embeds inside a target app as a TLS-encrypted server, while macOS tooling discovers, connects (with certificate fingerprint pinning via Bonjour), and sends commands to interact with the app's UI programmatically.

## Crew Roster

### Shared Foundation
| Crew Member | Alias | Primary Role |
|-------------|-------|-------------|
| [TheScore](01-THESCORE.md) | The Score | Shared wire protocol types (cross-platform) |

### Inside Team (iOS - runs in-process)
| Crew Member | Alias | Primary Role |
|-------------|-------|-------------|
| [TheFingerprints](03-THEFINGERPRINTS.md) | The Evidence | Visual touch indicators, overlay included in recordings |
| [TheSafecracker](04-THESAFECRACKER.md) | The Specialist | Touch injection, text input, gesture synthesis |
| [TheStakeout](05-THESTAKEOUT.md) | The Lookout | Screen recording, video encoding |
| [TheMuscle](06-THEMUSCLE.md) | The Bouncer | Authentication, session locking, on-device approval |
| [TheInsideJob](07-THEINSIDEJOB.md) | The Inside Operative | iOS server coordinator, message dispatch, UI polling, TLS transport |
| [ThePlant](08-THEPLANT.md) | The Advance Man | Zero-config auto-start via ObjC +load |
| [TheBagman](13-THEBAGMAN.md) | The Score Handler | Element registry, hierarchy parsing, target resolution, action execution, scroll orchestration, delta computation, screen capture |
| [TheTripwire](14-THETRIPWIRE.md) | The Early Warning System | Animation detection, VC identity, presentation layer fingerprinting |

### Cross-Cutting
| Dossier | Covers |
|---------|--------|
| [Unified Targeting](15-UNIFIED-TARGETING.md) | Element resolution pipeline: TheFence → ElementTarget → TheBagman.resolveTarget → action execution |

### Outside Team (macOS - CLI/MCP/Client)
| Crew Member | Alias | Primary Role |
|-------------|-------|-------------|
| [TheHandoff](02-THEHANDOFF.md) | The Logistics | Device discovery, TLS connection, keepalive, auto-reconnect, session state |
| [TheFence](10-THEFENCE.md) | The Boss | Centralized command dispatch, request-response correlation, async waits |
| [TheBookKeeper](16-THEBOOKKEEPER.md) | The Accountant | Session logs, artifact storage, compression, path safety |
| [ButtonHeistCLI](11-CLI.md) | The CLI | Command-line interface |
| [ButtonHeistMCP](12-MCP.md) | The MCP Server | AI agent tool interface |

## Module Dependency Graph

```mermaid
graph TD
    TheScore["TheScore — Shared Protocol"]
    TheInsideJob["TheInsideJob — iOS Server + Transport<br/><i>includes TheBagman, TheTripwire,<br/>TheSafecracker, TheMuscle, ThePlant</i>"]
    ButtonHeist["ButtonHeist — macOS Client Framework"]
    CLI["ButtonHeistCLI — CLI"]
    MCP["ButtonHeistMCP — MCP Server"]
    TestApp["BH Demo"]

    Crypto["swift-crypto"]
    X509["swift-certificates"]

    TheScore --> TheInsideJob
    Crypto --> TheInsideJob
    X509 --> TheInsideJob
    TheScore --> ButtonHeist
    ButtonHeist --> CLI
    ButtonHeist --> MCP
    TheInsideJob --> TestApp
```

> **Note:** TheBagman, TheTripwire, TheSafecracker, TheMuscle, TheStakeout, TheFingerprints, and ThePlant are all source groups compiled into the `TheInsideJob` framework target — they are not separate modules. They have separate dossiers because they are architecturally distinct subsystems with clear responsibilities.

## End-to-End Data Flow

```mermaid
sequenceDiagram
    participant CLI as CLI / MCP
    participant TF as TheFence
    participant TH as TheHandoff
    participant DC as DeviceConnection
    participant SS as SimpleSocketServer
    participant IJ as TheInsideJob
    participant TM2 as TheMuscle
    participant TS as TheSafecracker

    CLI->>TF: execute({"command":"activate","identifier":"btn"})
    TF->>TH: connectWithDiscovery()
    TH->>DC: connect(to: device)
    DC->>SS: TLS connect (cert fingerprint pinned via Bonjour TXT)
    SS->>TM2: onClientConnected
    TM2-->>DC: serverHello
    DC->>SS: clientHello
    TM2-->>DC: authRequired
    DC->>SS: authenticate(token)
    TM2-->>DC: info(ServerInfo)
    TH->>DC: send(.activate(target))
    DC->>SS: JSON + newline
    SS->>IJ: handleClientMessage
    IJ->>IJ: bagman.refreshAccessibilityData()
    IJ->>IJ: bagman.snapshotElements() (before)
    IJ->>TS: executeActivation(target)
    TS->>TS: resolve element, activate/tap
    TS-->>IJ: InteractionResult
    IJ->>IJ: computeDelta(before, after)
    IJ-->>DC: actionResult(delta)
    DC-->>TH: onActionResult
    TH-->>TF: callback → continuation resume
    TF-->>CLI: response JSON
```

## Cross-Cutting Review Concerns

These issues span multiple crew members and warrant holistic review:

1. ~~**Documentation drift**~~ - Fixed: configure() port param removed, isRunning visibility corrected, INSIDEJOB_BIND_ALL removed, token persistence clarified, InteractionEvent updated to use interfaceDelta
2. ~~**Duplicate error types**~~ - Fixed: `CLIError` removed, `FenceError` is the single error type
3. **Inconsistent timeouts** - 15s for actions, 30s for type_text/screenshots, 10s for interface requests
4. ~~**`vendorid` TXT key**~~ - Fixed: removed from DiscoveredDevice and DeviceDiscovery
5. ~~**Token logged in plaintext**~~ - Fixed: auth token now logged with `privacy: .sensitive` annotation; only visible when private data is enabled in Console
6. **No TheInsideJob unit tests** - TheMuscleTests added; TheBagman and TheInsideJob server-side logic still untested
7. **USBDeviceDiscovery blocks actor thread** - Subprocess calls in @ButtonHeistActor context
8. ~~**Interaction log payload unbounded**~~ - Fixed: capped at 500 events, uses InterfaceDelta instead of full snapshots
