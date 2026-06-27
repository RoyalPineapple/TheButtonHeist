<img width="1536" height="1024" alt="Noir-style heist planning board with an iPhone at center labeled The Vault, connected by red string to crew member dossiers: The Inside Job, The Safecracker, The Mastermind, The Fence, and The Bagman. A whiskey glass and desk lamp sit in the foreground." src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

[![CI](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RoyalPineapple/TheButtonHeist?label=release)](https://github.com/RoyalPineapple/TheButtonHeist/releases/latest)
[![License](https://img.shields.io/github/license/RoyalPineapple/TheButtonHeist)](LICENSE)

# The Button Heist

The Button Heist makes the iOS accessibility interface programmable.

Agents, humans, and tests act through the same contract VoiceOver depends on.

Every action is targeted and precise. The heist goes off clean, always returning with the evidence.

## One move

Begin with a single action:

```swift
Activate(.label("Pay"))
    .expect(.appeared(.label("Payment Complete")))
```

This is not "tap Pay." It is a contract:

- find the control the app declares as `Pay`
- perform the activation exposed by accessibility
- wait for the interface to settle
- prove that `Payment Complete` appeared
- return the receipt

The important question is not whether an event was delivered. It is whether the interface contract was fulfilled.

## Why this holds up

Contracts reduce ambiguity. The Button Heist asks the app what it declares now,
acts through that declaration, waits for the interface to settle, and returns
the evidence.

That changes the unit of automation:

- reusable product capabilities, not long transcripts of taps
- product semantics, not screen coordinates
- settled evidence, not sleeps
- the same heist language for agents and tests
- receipts you can assert, print, report, and compose

## First heist

A single move proves one contract. A heist defines a product capability.

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
    RunHeist("Cart.addItem", "Eggs")
    RunHeist("Cart.addItem", "Bread")
    WaitFor(.exists(.element(
        .label("subtotal"),
        .value(.contains("3 items"))
    )))
}
```

Each `Cart.addItem` call runs the same product capability with a new argument.
The heist owns the search, activation, settlement, and evidence. The caller says
what product move they want.

That is where the tool changes shape. The accessibility interface becomes the language of app interaction.

## Ways to run heists

Agents and tests use the same heist language. That is the practical payoff of
defining product capabilities against the accessibility contract.

- `perform(step:)` runs one Button Heist step from MCP.
- `list_heists` and `describe_heist` let an agent discover named capabilities.
- `run_heist(plan:)` runs a composed `HeistPlan` from MCP or the CLI.
- Checked-in Swift heist files compile to the same validated plan your tests can run.

Different doors. Same runtime. Same evidence.

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

Boring in the useful way: receipts say what ran, what changed, and where the machine stopped. They are not live handles, replay objects, or private runtime state. They are evidence you can assert against, print, report, and compose.

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

### 3. Drive the app

Agents usually start with `get_interface`, then use `perform(step:)` for one
semantic step or `run_heist(plan:)` for a named capability.

The CLI exposes the same runtime as terminal commands:

```bash
buttonheist list_devices
buttonheist get_interface
buttonheist activate --identifier loginButton
buttonheist type_text --text "Hello" --identifier nameField
buttonheist get_screen --output screen.png
```

For long-running automation, `json_lines` keeps one connection open and accepts one command per line:

```bash
printf '%s\n' '{"command":"get_interface"}' | buttonheist json_lines
```

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

Generated references live in [docs/reference](docs/reference/).

## Troubleshooting

### Device not appearing

Check that:

1. `TheInsideJob` is linked to the debug target.
2. The app is running in the foreground.
3. The connection scope allows simulator, USB, network, or the direct target you are using.
4. Bonjour/LAN discovery, if enabled, has the `_buttonheist._tcp` Info.plist entry.

### USB connection refused

Run:

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

- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot), used through [AccessibilitySnapshotBH](https://github.com/RoyalPineapple/AccessibilitySnapshotBH), handles UIKit accessibility hierarchy parsing. Patient infrastructure. The kind you want under a machine that acts on what the app says.

## License

Apache License 2.0. See [LICENSE](LICENSE).
