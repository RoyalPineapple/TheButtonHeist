---
date: 2026-02-19T10:41:47Z
researcher: aodawa
git_commit: 9cb0a1dfc34c62ad43cbf13e1e16d9990ab2cae2
branch: RoyalPineapple/codebase-review
repository: RoyalPineapple/accra
topic: "Comprehensive Codebase Review: Architecture, YAGNI, and Swift Idioms"
tags: [research, codebase, architecture, yagni, swift-concurrency, code-review]
status: complete
last_updated: 2026-02-19
last_updated_by: aodawa
---

# Research: Comprehensive Codebase Review

**Date**: 2026-02-19T10:41:47Z
**Researcher**: aodawa
**Git Commit**: 9cb0a1dfc34c62ad43cbf13e1e16d9990ab2cae2
**Branch**: RoyalPineapple/codebase-review
**Repository**: RoyalPineapple/accra

## Research Question

Comprehensive review of the ButtonHeist repository focusing on:
1. Architecture - overall system design, component interactions, layering, separation of concerns, protocol design
2. Overengineering/YAGNI - unnecessary abstractions, premature generalizations, unused flexibility, overly complex patterns
3. Modern and idiomatic Swift usage - concurrency, value types, protocol-oriented design, modern Swift features

---

## Part 1: Architecture Review

### System Overview

ButtonHeist is a distributed iOS accessibility automation system. An iOS app embeds `InsideMan` (server framework), which exposes the app's accessibility hierarchy and touch injection over local TCP. macOS clients connect via `ButtonHeist` (client framework) using Bonjour discovery. Three consumer targets exist: `Stakeout` (macOS SwiftUI GUI), `ButtonHeistCLI` (command-line tool), and `ButtonHeistMCP` (AI agent interface via Model Context Protocol).

### Module Dependency Graph

```
TheGoods          (cross-platform: iOS + macOS, zero deps)
    ^
Wheelman          (cross-platform: iOS + macOS, depends on TheGoods)
    ^               ^
InsideMan        ButtonHeist
(iOS only)       (macOS only)
    ^               ^
[iOS Apps]      Stakeout (macOS app)
                ButtonHeistCLI (macOS executable)
                ButtonHeistMCP (macOS executable)
```

**Layering is clean and disciplined:**

- **TheGoods** (`ButtonHeist/Sources/TheGoods/`) - Wire protocol types only. Imports only `Foundation` and `CoreGraphics`. Zero platform-specific code. Contains `Messages.swift` (all message types, payload structs, enums) and `BezierSampler.swift` (pure algorithm).

- **Wheelman** (`ButtonHeist/Sources/Wheelman/`) - Cross-platform networking primitives. Uses `Network.framework` (`NWConnection`, `NWBrowser`, `NWListener`). Does not decode message types - works in raw `Data`. Contains `SimpleSocketServer` (server), `DeviceConnection` (client), `DeviceDiscovery` (Bonjour browser), `DiscoveredDevice` (value type).

- **InsideMan** (`ButtonHeist/Sources/InsideMan/`) - iOS-only server. Wraps Wheelman's `SimpleSocketServer`, decodes `ClientMessage`, dispatches to accessibility APIs and touch injection. Entire module gated with `#if canImport(UIKit)` and `#if DEBUG`.

- **ButtonHeist** (`ButtonHeist/Sources/ButtonHeist/`) - macOS client facade. Two files: `HeistClient.swift` (connection management, state, APIs) and `Exports.swift` (`@_exported import TheGoods; @_exported import Wheelman`).

- **Stakeout**, **ButtonHeistCLI**, **ButtonHeistMCP** - Pure consumer targets. Import only `ButtonHeist`. Map their respective I/O formats to `ClientMessage` enum cases.

### Protocol Design

**Wire format**: Newline-delimited JSON (UTF-8) over TCP. `0x0A` byte separator. (`DeviceConnection.swift:55`, `SimpleSocketServer.swift:110-112`)

**Message types**: `ClientMessage` (22 cases) and `ServerMessage` (6 cases) are standard Swift `Codable` enums with associated values. Auto-synthesized encoding produces `{"activate":{"_0":{...}}}` keyed JSON. Only `ElementAction` has manual `Codable` (encodes as plain string). No `CodingKeys` enums anywhere.

**Discovery**: Bonjour `_buttonheist._tcp` with TXT record fields (`simudid`, `vendorid`). Service name format: `"{AppName}-{DeviceName}#{shortId}"`.

### HeistClient Dual API Design

`HeistClient` (`HeistClient.swift:9-10`) serves three consumption patterns simultaneously:

1. **SwiftUI (Reactive)**: `@Published public private(set) var` properties (7 total) for `ObservableObject` binding
2. **Callbacks (Imperative)**: Optional closure properties (`onDeviceDiscovered`, `onConnected`, etc.) for CLI/MCP
3. **Async/Await (Sequential)**: `waitForActionResult(timeout:)` and `waitForScreen(timeout:)` using `withCheckedThrowingContinuation`

This is pragmatic - the same framework genuinely serves three different consumption patterns (SwiftUI app, async MCP server, callback-driven CLI).

### Connection Architecture

**Server side** (`SimpleSocketServer`): `NWListener` on IPv6 any (`::`) with dual-stack. `NSLock`-protected client dictionary. `@unchecked Sendable`. Runs on private `DispatchQueue`.

**Client side** (`DeviceConnection`): `NWConnection` with Bonjour endpoint resolution. `@MainActor` annotated. Recursive receive loop. NW callbacks bridged to main actor via `Task { @MainActor in }`.

### InsideMan Internal Architecture

`InsideMan` (`InsideMan.swift:18`) is a `@MainActor public final class` singleton managing:
- `SimpleSocketServer` + `NetService` (Bonjour advertisement)
- `AccessibilityHierarchyParser` for UI tree walking
- Interactive object cache (`[Int: WeakObject]`) - weak references to live `NSObject`s keyed by traversal index
- `SafeCracker` for touch synthesis + text input
- Polling timer (configurable interval, hash-based change detection)
- Debounce timer (300ms for accessibility notifications)
- Delta computation (before/after element diffing with animation settling)

---

## Part 2: Overengineering / YAGNI Analysis

### 2.1 Duplicate Device Matching Logic (3 copies)

The same 6-field device filter predicate is copy-pasted identically in three locations:

- `ButtonHeistMCP/Sources/main.swift:794-804` (`matchDevice`)
- `ButtonHeistCLI/Sources/DeviceConnector.swift:74-86` (`matchingDevice`)
- `ButtonHeistCLI/Sources/CLIRunner.swift:93-100` (inline in callback)

All use identical lowercased `contains` on name/appName/deviceName and `hasPrefix` on shortId/simulatorUDID/vendorIdentifier. This could be a single method on `DiscoveredDevice` or `[DiscoveredDevice]` in the shared `Wheelman` module.

### 2.2 TypeCommand Duplicates DeviceConnector

`TypeCommand` (`ButtonHeistCLI/Sources/TypeCommand.swift:54-108`) manually implements its own discovery/connection loop with hardcoded timeouts, duplicating the logic already centralized in `DeviceConnector`. All other CLI commands (`ActionCommand`, `TouchCommand`, `ScreenshotCommand`) correctly use `DeviceConnector`. Additionally, `TypeCommand` does not respect the `--device` filter flag, always connecting to the first device found.

### 2.3 DeviceInfo Struct Defined Twice

An identical `DeviceInfo: Encodable` struct with the same 6 fields is defined locally in both:
- `ButtonHeistCLI/Sources/ListCommand.swift:42-44`
- `ButtonHeistMCP/Sources/main.swift:385-386`

Both map from `DiscoveredDevice` the same way. This could live as a shared `Encodable` extension on `DiscoveredDevice` in `Wheelman`.

### 2.4 CLI Test Duplication (Structural Constraint)

`ButtonHeistCLI/Tests/FormattingTests.swift:143-166` copies `formatElement` and `formatInterfaceJSON` verbatim from `CLIRunner.swift` because the CLI is an executable target that cannot be imported by tests. Similarly, `ExitCodeTests.swift:4-10` re-declares the `ExitCode` enum. This is a known Swift packaging constraint, not overengineering.

### 2.5 Unused Code

| Item | Location | Status |
|------|----------|--------|
| `ActionError.notConnected` | `HeistClient.swift:229-240` | Defined but never thrown or caught anywhere |
| `InsideManCore` product | `ButtonHeist/Package.swift:14` | Declared but no target depends on it |
| `BezierSampler.sampleCubicBezier` | `BezierSampler.swift:15-25` | `public` but only called from `sampleBezierPath` in same file |
| `DeviceConnection` callback properties | `DeviceConnection.swift:18-24` | All 7 are `public` but only accessed by `HeistClient` |

### 2.6 Unused Design System Tokens

In `Stakeout/Sources/Design/`:

**Colors.swift** - 4 of 7 tokens unused:
- `Color.Tree.background` - 0 usages
- `Color.Tree.rowHover` - 0 usages
- `Color.Tree.rowSelected` - 0 usages
- `Color.Tree.divider` - 0 usages

**Typography.swift** - ALL 5 `Font.Tree.*` tokens are unused. Views use inline `.font(.system(...))` instead.

**Spacing.swift** - `TreeSpacing.rowVerticalPadding` is unused.

### 2.7 Gesture Target Structs - Dual-Mode Design

Every gesture target struct (e.g., `LongPressTarget`, `SwipeTarget`, `PinchTarget`) has both `elementTarget: ActionTarget?` and explicit coordinate fields (`pointX/Y`, `startX/Y`, etc.), all optional. Callers always use exactly one mode. The MCP handler at `main.swift:433-445` always branches into either element-based or coordinate-based construction, never both. This is a reasonable wire-protocol design choice (not overengineering) since it keeps the protocol flat and simple for external consumers.

### 2.8 ActionResult Fields That Are Almost Always Nil

`ActionResult` (`Messages.swift:434-461`) has `message: String?`, `value: String?`, `interfaceDelta: InterfaceDelta?`, and `animating: Bool?`. The `value` field is only populated for `typeText` operations. The `interfaceDelta` field is computed for every action but often `.noChange`. These optionals are justified by the protocol's design - a single response type for all operations.

---

## Part 3: Modern and Idiomatic Swift Usage

### 3.1 Concurrency Model - Excellent

**Swift 6 strict concurrency throughout.** All three production packages compile with `.swiftLanguageMode(.v6)`. Zero compiler warnings suppressed.

**`@MainActor` is the primary isolation strategy.** Rather than using `actor` types, the codebase annotates classes with `@MainActor` and uses `Task { @MainActor in }` to bridge from non-isolated Network.framework callbacks. This is the correct pattern for a codebase that's fundamentally UI-driven (UIKit on iOS, SwiftUI on macOS).

**No actors defined.** The MCP server's `Server` type (from the swift-sdk dependency) is the only actor in the system. `HeistClient`, `InsideMan`, and all other classes use `@MainActor` annotation instead. This avoids the complexity of custom actor isolation while maintaining full Swift 6 compliance.

**Structured concurrency patterns used correctly:**
- `Task { @MainActor in }` for NW callback bridging (`DeviceConnection.swift:35-39`, `DeviceDiscovery.swift:31-34`, `InsideMan.swift:79-83`)
- `Task` with cancellation for timers/polling (`InsideMan.swift:358-365`, `InsideMan.swift:389-399`)
- `withCheckedThrowingContinuation` for callback-to-async bridging (`HeistClient.swift:160-182`, `main.swift:720-736`)
- Only one `Task.detached` in the entire codebase (`CLIRunner.swift:253-266` for raw stdin reading)

**GCD usage is minimal and justified.** Only 3 occurrences:
- `DispatchQueue` as NW framework queue parameter (`SimpleSocketServer.swift:26`) - required by API
- Two `DispatchQueue.main.asyncAfter` for animation delays in UI code

### 3.2 Sendable Conformance - Correct

- All `TheGoods` structs explicitly conform to `Sendable` (auto-synthesized, all stored properties are `Sendable`)
- `SimpleSocketServer` uses `@unchecked Sendable` with documented `NSLock` protection
- `@Sendable` annotations on closure callback types in `SimpleSocketServer`
- No incorrect `@unchecked Sendable` usage found

### 3.3 Value Types vs Reference Types - Appropriate

**Structs** used for: all wire protocol types (~25 structs in `Messages.swift`), `DiscoveredDevice`, all SwiftUI views, all CLI command types.

**Classes** used only where required: `ObservableObject` conformance (`HeistClient`), stateful networking objects (`DeviceConnection`, `SimpleSocketServer`), UIKit subclasses, singleton lifecycle (`InsideMan`), mutable touch state (`SafeCracker`).

No cases where a class should be a struct or vice versa.

### 3.4 Codable Strategy - Clean

Auto-synthesized `Codable` for all structs. No `CodingKeys` enums anywhere in the codebase. Only `ElementAction` has manual `Codable` (encodes open-ended custom action names as plain strings). `JSONEncoder`/`JSONDecoder` created at send/receive call sites. This keeps the wire format directly tied to Swift property names - simple and debuggable.

### 3.5 Modern Swift Features Used

| Feature | Usage |
|---------|-------|
| `if let` shorthand (SE-0345) | Throughout (`if let error`, `guard let self`) |
| `some` opaque return types | All SwiftUI `body` properties |
| `#Preview` macro | Stakeout views (`HierarchyListView.swift:192`, `HierarchyTreeView.swift:162`) |
| `@Previewable @State` | Inside `#Preview` blocks |
| `@ViewBuilder` | `ContentView.swift:39-41` for computed view properties |
| `indirect enum` | `ElementNode` recursive tree type (`Messages.swift:700`) |
| `@_exported import` | `Exports.swift` for facade pattern |
| `@_cdecl` | `InsideMan.swift:1491` for ObjC interop |
| `@convention(c)` | `SyntheticTouchFactory`, `IOHIDEventBuilder` for C function pointers |

### 3.6 What's NOT Used (and whether it matters)

| Feature | Status | Assessment |
|---------|--------|------------|
| `@Observable` / `@Bindable` | Not used. `HeistClient` uses legacy `ObservableObject` + `@Published` | **Worth migrating.** The Observation framework (iOS 17+/macOS 14+) is more efficient and eliminates unnecessary view re-renders. Since minimum deployment is already iOS 17/macOS 14, `@Observable` is available. `@StateObject` would become a plain `@State` reference. |
| `any` existentials | Not used | Not needed. The codebase uses concrete types and `some` everywhere. No existential boxing occurs. |
| `consuming`/`borrowing` | Not used | Not needed. No performance-critical ownership scenarios. |
| Custom `@propertyWrapper` | Not used | Not needed. No cross-cutting property concerns. |
| Custom `@resultBuilder` | Not used | Not needed. Only SwiftUI's `@ViewBuilder` is used. |
| `nonisolated` | Not used | Could be useful on `HeistClient`'s pure computed properties but not critical. |
| `Result<>` type | Not used | Fine. All error handling uses `throws`/`try`/`catch`. No need for `Result`. |

### 3.7 Error Handling - Adequate

Two patterns used consistently:
1. `enum : Error, LocalizedError` with `errorDescription` (HeistClient)
2. `enum : Error, CustomStringConvertible` with `description` (CLI)

`try?` used liberally for non-critical paths (JSON encoding, sleep cancellation). No force-unwraps (`!`) found in production code.

### 3.8 Access Control - Good

`public private(set)` on all `@Published` properties in `HeistClient`. `private` used extensively in `InsideMan` for implementation details. Internal access (implicit) for CLI/app-only types. Some items could be tightened:
- `DeviceConnection` callback properties are `public` but only accessed by `HeistClient`
- `BezierSampler.sampleCubicBezier` is `public` but only called internally

---

## Summary of Actionable Findings

### Architecture (Strong)
- Clean layered dependency graph with no circular dependencies
- Proper separation: TheGoods (protocol), Wheelman (network), InsideMan (server), ButtonHeist (client)
- `#if DEBUG` gating prevents InsideMan from shipping in release builds
- Wire protocol is simple and well-documented

### YAGNI Issues (Moderate)
1. **Device matching logic duplicated 3x** - consolidate to shared module
2. **TypeCommand bypasses DeviceConnector** - should use it like all other commands
3. **DeviceInfo struct duplicated** - move to shared location
4. **Unused design system tokens** - 4 color tokens, all 5 font tokens, 1 spacing token unused
5. **ActionError.notConnected** - dead code
6. **InsideManCore product** - declared but unused

### Swift Idioms (Strong with one notable gap)
1. **`ObservableObject` -> `@Observable`** - The single most impactful modernization. `HeistClient` could use `@Observable` since the project already targets iOS 17+/macOS 14+. This would eliminate Combine dependency, improve SwiftUI performance (fine-grained observation), and simplify consumption (`@State` instead of `@StateObject`).
2. Everything else is excellent: Swift 6, structured concurrency, proper `Sendable`, value types where appropriate, modern `if let` shorthand, `#Preview` macros.

---

## Code References

- `Project.swift:21-107` - Tuist target definitions and dependency graph
- `ButtonHeist/Package.swift:1-63` - SPM package structure
- `ButtonHeist/Sources/TheGoods/Messages.swift` - All wire protocol types
- `ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift` - TCP server implementation
- `ButtonHeist/Sources/Wheelman/DeviceConnection.swift` - TCP client implementation
- `ButtonHeist/Sources/ButtonHeist/HeistClient.swift` - macOS client with dual API
- `ButtonHeist/Sources/InsideMan/InsideMan.swift` - iOS server (~1500 lines)
- `ButtonHeist/Sources/InsideMan/SafeCracker.swift` - Touch synthesis
- `ButtonHeistMCP/Sources/main.swift` - MCP server (19 tools)
- `ButtonHeistCLI/Sources/` - CLI command hierarchy
- `Stakeout/Sources/` - macOS SwiftUI inspector app

## Open Questions

1. Is the `Interface.tree` optional field still needed? Only consumed by Stakeout's tree view toggle, and the flat `elements` array is the primary consumer path.
2. Should the `InsideManCore` product be removed or is there a planned use case?
3. Would migrating from `ObservableObject` to `@Observable` break any consumers?
