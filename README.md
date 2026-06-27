<img width="1536" height="1024" alt="Noir-style heist planning board with an iPhone at center labeled The Vault, connected by red string to crew member dossiers: The Inside Job, The Safecracker, The Mastermind, The Fence, and The Bagman. A whiskey glass and desk lamp sit in the foreground." src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

[![CI](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RoyalPineapple/TheButtonHeist?label=release)](https://github.com/RoyalPineapple/TheButtonHeist/releases/latest)
[![License](https://img.shields.io/github/license/RoyalPineapple/TheButtonHeist)](LICENSE)

# The Button Heist

The Button Heist makes the settled accessibility interface executable. Agents and tests act through labels, values, traits, state, and declared actions. Each step waits for the interface to settle, then returns evidence that the contract changed as expected.

That is the project: product semantics in, settled evidence out.

A UI automation step often starts with an event. The Button Heist starts with the contract the app already exposes to assistive technologies. It asks what exists, what can act, and what must be true afterward.

## One move

The whole machine is visible in one move:

```swift
Activate(.label("Pay"))
    .expect(.appeared(.label("Payment Complete")))
```

This is not "tap Pay." It means: resolve the control declared as `Pay`, perform its accessibility activation, wait for the app to settle, prove that `Payment Complete` appeared in the settled accessibility interface, and return the receipt.

The important question is not whether an event was delivered. It is whether the interface contract was fulfilled.

## What it unlocks

With that loop, The Button Heist can:

- target product semantics, not screen coordinates
- type into fields and prove the semantic value changed
- wait through async UI until a confirmation, result, or error state appears
- compose multi-step flows into named product capabilities
- let agents inspect those capabilities before they call them
- leave CI with a receipt that names the contract that broke

Accessibility is the interface. Strip an app of rendering and it is still talking: labels, values, traits, hierarchy, state, and actions. The Button Heist listens to that interface, makes one declared move, and brings back what changed.

## Quick start

### 1. Add `TheInsideJob`

Link `TheInsideJob` to your debug target. It starts a local TCP server via ObjC `+load`; no app setup code is required. Release builds do not start the server.

```swift
import SwiftUI
import TheInsideJob

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

By default the server accepts simulator loopback and USB-scoped connections. It does not publish Bonjour on the LAN unless you opt into network scope with `INSIDEJOB_SCOPE=simulator,usb,network` or `InsideJobScope`.

If you enable network scope, add the Bonjour permissions:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with The Button Heist.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### 2. Install the tools

```bash
brew install RoyalPineapple/tap/buttonheist
```

The Homebrew distribution currently supports Apple Silicon macOS only.

Add the MCP server to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "buttonheist-mcp",
      "args": []
    }
  }
}
```

Agents usually start with `get_interface`, then act with commands such as `activate`, `type_text`, `rotor`, `wait`, and `run_heist`.

### 3. Use the CLI directly

```bash
buttonheist list_devices
buttonheist get_interface
buttonheist activate --identifier loginButton
buttonheist type_text --text "Hello" --identifier nameField
buttonheist get_screen --output screen.png
```

`json_lines` keeps one connection open and accepts canonical machine JSON objects. Direct CLI commands and MCP tools project from the same Fence command contract.

```bash
printf '%s\n' '{"command":"get_interface"}' | buttonheist json_lines
```

## First heist

Use `perform(step:)` for one instruction. Use `run_heist(plan:)` when the interaction deserves a name.

Rendered as canonical source for `run_heist(plan:)`:

```swift
HeistPlan("shop") {
    HeistDef<String>("Cart.addItem", parameter: "item") { item in
        TypeText(item, into: .label("Search Items"))
            .expect(.exists(.element(.label("Search Items"), .value(item))))

        Activate(.label(item))
            .expect(.appeared(.element(
                .label(.prefix(item)),
                .identifier(.contains("cart"))
            )))
    }

    RunHeist("Cart.addItem", "Milk")
}
```

`Cart.addItem("Milk")` is now a product capability. It is still grounded in accessibility predicates and receipts, but callers can work at the level of the product: search, add to cart, checkout.

## Receipts

A receipt is the durable answer to "what happened?" Not a hunch. Not a tap log. The facts.

```text
step: Activate(label: "Pay")
status: passed
before: Checkout
after: Payment
delta: screen changed
evidence:
  appeared: "Payment" [header]
  appeared: "Total $41.00" [staticText]
```

When a step cannot satisfy the contract, the evidence matters more:

```text
activate -> error[elementNotFound]
No match for: label="Calamari Fritti"
near miss:
  "Calamari Fritti, $14.00, Calamari Fritti" [button]
known elements:
  "Start drawer" [header]
  "Save" [button]
```

Receipts are intentionally plain. Boring in the useful way: they say what ran, what changed, and where the machine stopped. They are not live handles, replay objects, or private runtime state. They carry evidence you can assert against, print, report, or use to compose the next heist.

## Authoring surfaces

The Button Heist has three public authoring surfaces:

- `perform(step:)` runs one ButtonHeist instruction from MCP.
- `run_heist(plan:)` runs canonical ButtonHeist source from MCP or the CLI.
- Checked-in Swift files compile to a validated `HeistPlan` for local authoring.

All three lower to the same runtime. A generated `.heist` package is an artifact, not a hand-authored source file. Raw JSON IR is for generated tooling and diagnostics.

## Screenshots and gestures

Screenshots are visual evidence. They show the rendered interface, and The Button Heist can capture them when pixels are the right proof.

They are not the normal way to act. For buttons, fields, menus, actions, rotors, waits, and product flows, the durable control surface is the accessibility contract the app already owes its users.

Explicit mechanical gestures stay available for maps, canvases, drawing surfaces, games, and spatial products. Those are intentional spatial interactions, not setup steps for ordinary controls.

## Documentation

| Need | Read |
|---|---|
| Understand the contract loop | [Accessibility contract](docs/ACCESSIBILITY-CONTRACT.md), [Architecture](docs/ARCHITECTURE.md) |
| Connect an agent | [MCP agent guide](docs/MCP-AGENT-GUIDE.md), [ButtonHeistMCP](ButtonHeistMCP/) |
| Use the terminal | [ButtonHeistCLI](ButtonHeistCLI/), [Command reference](docs/reference/commands.md) |
| Author heists | [Swift heist authoring](docs/SWIFT-HEIST-AUTHORING.md), [Heist format](docs/HEIST-FORMAT.md), [Examples](examples/README.md) |
| Integrate an app | [API](docs/API.md), [Auth](docs/AUTH.md), [USB connectivity](docs/USB_DEVICE_CONNECTIVITY.md) |
| See evidence and experiments | [Benchmarks](docs/BENCHMARKS.md), [Heist Doctor](docs/HEIST-DOCTOR.md) |

All docs start at [docs/README.md](docs/README.md). Generated references live in [docs/reference](docs/reference/).

## Troubleshooting

### Device not appearing

Check that:

1. `TheInsideJob` is linked to the debug target.
2. The app is running in the foreground.
3. The connection scope allows simulator, USB, network, or the direct target you are using.
4. Bonjour/LAN discovery, if enabled, has the `_buttonheist._tcp` Info.plist entry.

### USB connection refused

Check:

```bash
xcrun devicectl list devices
lsof -i -P -n | grep CoreDev
```

The app must be running on the device.

### Empty hierarchy

Make sure the app has an interface on a screen and that the root view exposes an accessibility hierarchy. Then run:

```bash
buttonheist get_interface
```

## Development

### Prerequisites

- Xcode with Swift 6 package support
- iOS 17+ / macOS 14+
- [Tuist](https://tuist.io)

### Build locally

```bash
git submodule update --init --recursive
tuist generate
open ButtonHeist.xcworkspace
```

### Test locally

```bash
tuist test TheScoreTests --no-selective-testing
tuist test ButtonHeistTests --no-selective-testing
tuist test TheInsideJobTests --platform ios --device "iPhone 16 Pro" --os 26.1 --no-selective-testing
```

### Project structure

```text
ButtonHeist/
+-- ButtonHeist/Sources/          # Core frameworks
+-- ButtonHeistCLI/               # CLI tool
+-- ButtonHeistMCP/               # MCP server
+-- TestApp/                      # SwiftUI + UIKit test apps
+-- submodules/AccessibilitySnapshotBH/
+-- docs/                         # Architecture, contracts, API, connectivity
+-- examples/                     # Canonical semantic examples
```

## Acknowledgments

- [KIF (Keep It Functional)](https://github.com/kif-framework/KIF). The Button Heist owes part of its lineage to KIF's long accessibility-first history on iOS.
- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot). Used for parsing UIKit accessibility hierarchies via [AccessibilitySnapshotBH](https://github.com/RoyalPineapple/AccessibilitySnapshotBH).

## License

Apache License 2.0. See [LICENSE](LICENSE).
