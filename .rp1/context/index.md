# ButtonHeist - Project Index

> Generated: 2025-03-10 | Commit: ee2a60b | Strategy: parallel-map-reduce (incremental)

## Overview

**Button Heist** gives AI agents and humans full programmatic control over iOS apps. Embed TheInsideJob in your iOS app, then connect via MCP server or CLI to inspect UI, tap buttons, swipe, type, and navigate over a persistent TCP connection.

- **Version**: 0.0.1
- **Language**: Swift 6.0 (strict concurrency), Objective-C (minor)
- **Platforms**: iOS 17.0+ (server framework), macOS 14.0 (client tooling)
- **Build System**: Tuist (Xcode project generation) + Swift Package Manager (CLI, MCP)
- **Build Policy**: `-warnings-as-errors` on all SPM targets
- **License**: Apache License 2.0

## Frameworks & Dependencies

| Dependency | Purpose |
|-----------|---------|
| UIKit / SwiftUI | Accessibility hierarchy, touch injection, test apps |
| Network.framework | TCP server/client (NWListener, NWConnection), Bonjour (NWBrowser) |
| IOKit (private) | Multi-finger HID event synthesis for touch injection |
| AVFoundation | H.264/MP4 screen recording via AVAssetWriter |
| AccessibilitySnapshot | Forked submodule for accessibility hierarchy parsing |
| swift-argument-parser 1.3.0+ | CLI command/option parsing |
| MCP swift-sdk 0.11.0+ | Model Context Protocol server for AI agent tools |

## Project Structure

```
ButtonHeist/
├── ButtonHeist/Sources/
│   ├── TheScore/                 # Shared wire protocol types (iOS + macOS)
│   ├── TheInsideJob/             # iOS server: accessibility, gestures, TCP
│   │   ├── TheInsideJob.swift + TheInsideJob+Dispatch.swift
│   │   ├── TheBagman.swift + TheBagman+Conversion.swift
│   │   ├── TheSafecracker/       # Touch injection (7 files, split by concern)
│   │   ├── TheMuscle.swift, TheStakeout.swift, TheFingerprints.swift
│   │   └── Extensions/
│   ├── TheGetaway/               # Cross-platform TCP transport layer
│   ├── TheButtonHeist/           # macOS client
│   │   ├── TheFence.swift + TheFence+Handlers.swift + TheFence+Formatting.swift
│   │   ├── TheFence+CommandCatalog.swift
│   │   ├── TheMastermind.swift
│   │   ├── TheHandoff/           # Connection lifecycle
│   │   └── ButtonHeistActor.swift, Exports.swift
│   └── ThePlant/                 # ObjC +load auto-start hook
├── ButtonHeist/Tests/            # Unit tests for all modules
├── ButtonHeistMCP/               # MCP server (14 tools, macOS)
├── ButtonHeistCLI/               # CLI tool (29 commands, macOS)
├── TestApp/                      # SwiftUI + UIKit demo apps
├── AccessibilitySnapshot/        # Git submodule (hierarchy parsing fork)
├── ai-fuzzer/                    # Git submodule: autonomous AI app fuzzing
├── docs/                         # Architecture, API, protocol, USB, auth docs
├── docs/dossiers/                # Per-component design dossiers
├── scripts/                      # Release automation
├── Tuist/                        # External dependencies + helpers
├── Project.swift                 # Tuist project definition
└── Workspace.swift               # Tuist workspace definition
```

## Entry Points

| Entry Point | Purpose |
|------------|---------|
| `TheInsideJob.swift` | iOS server singleton - TCP server, Bonjour, UI polling |
| `TheInsideJob+Dispatch.swift` | iOS server command dispatch routing |
| `TheMastermind.swift` | macOS observable coordinator - discovery, connection, callbacks |
| `TheFence.swift` | Command dispatch core - connection management and send/await |
| `TheFence+Handlers.swift` | Command handler implementations |
| `TheFence+Formatting.swift` | FenceResponse enum and output formatting |
| `ThePlantAutoStart.m` | ObjC +load entry point - boots TheInsideJob before Swift runs |
| `ButtonHeistCLI/Sources/` | CLI entry point - ArgumentParser commands through TheFence |
| `ButtonHeistMCP/Sources/` | MCP server entry point - JSON-RPC over stdio through TheFence |

## Quick Start

```bash
# Clone with submodules
git clone --recursive <repo-url>

# Build frameworks
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScore build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJob -destination 'generic/platform=iOS' build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build

# Build CLI
cd ButtonHeistCLI && swift build -c release
export PATH="$PWD/.build/release:$PATH"

# Build MCP server
cd ButtonHeistMCP && swift build -c release

# Run test app on simulator
SIM_UDID=$(xcrun simctl list devices available | grep iPhone | head -1 | grep -oE '[A-F0-9-]{36}')
xcrun simctl boot "$SIM_UDID"
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp

# Verify Bonjour discovery
timeout 5 dns-sd -B _buttonheist._tcp .

# Run tests
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScoreTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJobTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Key Documentation

| Document | Path |
|----------|------|
| Architecture | `docs/ARCHITECTURE.md` |
| Public API | `docs/API.md` |
| Wire Protocol | `docs/WIRE-PROTOCOL.md` |
| Authentication | `docs/AUTH.md` |
| USB Connectivity | `docs/USB_DEVICE_CONNECTIVITY.md` |
| Versioning | `docs/VERSIONING.md` |
| Component Dossiers | `docs/dossiers/` |

## Submodules

| Submodule | Remote | Branch | Purpose |
|-----------|--------|--------|---------|
| AccessibilitySnapshot | RoyalPineapple/AccessibilitySnapshot | buttonheist | Accessibility hierarchy parsing with elementVisitor + Hashable |
| ai-fuzzer | separate repo | - | Autonomous iOS app fuzzer built on Button Heist |
