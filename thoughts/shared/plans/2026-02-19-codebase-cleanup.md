# Codebase Cleanup Implementation Plan

## Overview

Address 6 findings from the codebase architecture review: deduplicate device matching logic, fix TypeCommand to use DeviceConnector, remove dead code, clean unused design tokens, and migrate HeistClient from `ObservableObject` to `@Observable`.

## Current State Analysis

The codebase is well-architected with clean module boundaries, but has accumulated some duplication across the CLI and MCP consumer targets, unused design system tokens in Stakeout, and one modernization opportunity (`@Observable`).

### Key Discoveries:
- Device matching logic copy-pasted 3x: `main.swift:794-805`, `DeviceConnector.swift:74-87`, `CLIRunner.swift:93-100`
- `TypeCommand` reimplements `DeviceConnector` inline (lines 54-108), lacks `--device` support
- `ActionError.notConnected` defined at `HeistClient.swift:231` but never thrown
- `InsideManCore` product declared at `Package.swift:15` with no consumers
- All 5 `Font.Tree.*` tokens and 4/7 `Color.Tree.*` tokens are unused
- `HeistClient` uses legacy `ObservableObject` but targets iOS 17+/macOS 14+

## Desired End State

After this plan:
- Device matching is a single method on `DiscoveredDevice`, called from all 3 consumer sites
- `TypeCommand` uses `DeviceConnector` and supports `--device` like all other commands
- No dead code (`ActionError.notConnected`, `InsideManCore`, unused design tokens)
- `DeviceConnection` callbacks have appropriate access control
- `BezierSampler.sampleCubicBezier` is `internal` (only called from same file)
- `HeistClient` uses `@Observable` macro

### Verification:
```bash
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test
cd ButtonHeistMCP && swift build && cd ..
cd ButtonHeistCLI && swift build && cd ..
```

## What We're NOT Doing

- Refactoring the gesture target struct dual-mode design (element vs coordinates) — this is a reasonable protocol choice
- Extracting CLI test duplications (`formatElement`, `ExitCode`) — these are a Swift packaging constraint
- Migrating Stakeout to use the design tokens it doesn't currently use — just removing the unused ones
- Adding new tests — only verifying existing tests still pass

## Implementation Approach

Five independent, atomic phases. Each can be built and tested in isolation. Order matters only for Phase 1 (must come before Phase 2, since Phase 2's CLIRunner changes depend on the new `matches(filter:)` method).

---

## Phase 1: Consolidate Device Matching

### Overview
Add a `matches(filter:)` method to `DiscoveredDevice` and a `first(matching:)` extension on `Array<DiscoveredDevice>`. Replace all three duplicate implementations.

### Changes Required:

#### 1. Add matching method to DiscoveredDevice
**File**: `ButtonHeist/Sources/Wheelman/DiscoveredDevice.swift`
**Changes**: Add `matches(filter:)` method and array extension after the existing type

After line 66 (end of `deviceName` computed property), before the closing `}` of the struct, add:

```swift
    /// Check if this device matches a filter string.
    /// Matches case-insensitively: contains on name/appName/deviceName, prefix on shortId/simulatorUDID/vendorIdentifier.
    public func matches(filter: String) -> Bool {
        let low = filter.lowercased()
        return name.lowercased().contains(low) ||
            appName.lowercased().contains(low) ||
            deviceName.lowercased().contains(low) ||
            (shortId?.lowercased().hasPrefix(low) ?? false) ||
            (simulatorUDID?.lowercased().hasPrefix(low) ?? false) ||
            (vendorIdentifier?.lowercased().hasPrefix(low) ?? false)
    }
```

After the struct closing brace, add the array extension:

```swift
extension Array where Element == DiscoveredDevice {
    /// Return the first device matching the filter, or the first device if filter is nil.
    public func first(matching filter: String?) -> DiscoveredDevice? {
        guard let filter else { return first }
        return first { $0.matches(filter: filter) }
    }
}
```

#### 2. Replace MCP's matchDevice function
**File**: `ButtonHeistMCP/Sources/main.swift`
**Changes**: Delete the `matchDevice` function (lines 794-805) and update its two call sites

Replace call at ~line 771 in `discoverAndConnect`:
```swift
// Before:
if let device = matchDevice(from: client.discoveredDevices, filter: deviceFilter) {
// After:
if let device = client.discoveredDevices.first(matching: deviceFilter) {
```

Replace call at ~line 832 in `onDisconnected` reconnect loop:
```swift
// Before:
if let device = matchDevice(from: client.discoveredDevices, filter: deviceFilter) {
// After:
if let device = client.discoveredDevices.first(matching: deviceFilter) {
```

Delete the `matchDevice` function entirely.

#### 3. Replace DeviceConnector's matchingDevice function
**File**: `ButtonHeistCLI/Sources/DeviceConnector.swift`
**Changes**: Replace `matchingDevice()` (lines 74-87) with a one-liner

```swift
private func matchingDevice() -> DiscoveredDevice? {
    client.discoveredDevices.first(matching: deviceFilter)
}
```

#### 4. Replace CLIRunner's inline matching
**File**: `ButtonHeistCLI/Sources/CLIRunner.swift`
**Changes**: Replace inline matching logic at lines 92-100

```swift
// Before (lines 92-100):
if let filter = self.options.device {
    let low = filter.lowercased()
    let matches = device.name.lowercased().contains(low) ||
        device.appName.lowercased().contains(low) ||
        device.deviceName.lowercased().contains(low) ||
        (device.shortId?.lowercased().hasPrefix(low) ?? false) ||
        (device.simulatorUDID?.lowercased().hasPrefix(low) ?? false) ||
        (device.vendorIdentifier?.lowercased().hasPrefix(low) ?? false)
    guard matches else { return }
}

// After:
if let filter = self.options.device {
    guard device.matches(filter: filter) else { return }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] All targets build: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build`
- [ ] MCP builds: `cd ButtonHeistMCP && swift build`
- [ ] CLI builds: `cd ButtonHeistCLI && swift build`
- [ ] Wheelman tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test`

---

## Phase 2: Fix TypeCommand to Use DeviceConnector

### Overview
Replace TypeCommand's inline discovery/connection logic with `DeviceConnector` and add the `--device` option.

### Changes Required:

#### 1. Rewrite TypeCommand
**File**: `ButtonHeistCLI/Sources/TypeCommand.swift`
**Changes**: Add `--device` option, replace lines 54-108 with DeviceConnector pattern

Add after the `quiet` flag (line 37):

```swift
@Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
var device: String?
```

Replace lines 54-108 (from `let client = HeistClient()` through the `defer` block) with:

```swift
let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
try await connector.connect()
defer { connector.disconnect() }
let client = connector.client
```

The remaining lines (send message, wait for result, output) stay the same but now reference the `client` from the connector.

Remove `import Darwin` from line 3 only if `Darwin.exit(1)` at line 130 is no longer needed. Check: it is still needed for the failure exit code, so keep `import Darwin`.

### Success Criteria:

#### Automated Verification:
- [ ] CLI builds: `cd ButtonHeistCLI && swift build`
- [ ] CLI tests pass: `cd ButtonHeistCLI && swift test`

---

## Phase 3: Remove Dead Code

### Overview
Remove unused code: `ActionError.notConnected`, `InsideManCore` product, tighten access control on `DeviceConnection` callbacks and `BezierSampler.sampleCubicBezier`.

### Changes Required:

#### 1. Remove ActionError.notConnected
**File**: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
**Changes**: Remove the `.notConnected` case and its `errorDescription` branch

```swift
// Before (lines 229-241):
public enum ActionError: Error, LocalizedError {
    case timeout
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Action timed out"
        case .notConnected:
            return "Not connected to device"
        }
    }
}

// After:
public enum ActionError: Error, LocalizedError {
    case timeout

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Action timed out"
        }
    }
}
```

#### 2. Remove InsideManCore product
**File**: `ButtonHeist/Package.swift`
**Changes**: Delete line 15

```swift
// Delete this line:
.library(name: "InsideManCore", targets: ["InsideMan"]),
```

#### 3. Make BezierSampler.sampleCubicBezier internal
**File**: `ButtonHeist/Sources/TheGoods/BezierSampler.swift`
**Changes**: Change `public` to `internal` on line 15

```swift
// Before:
public static func sampleCubicBezier(

// After:
static func sampleCubicBezier(
```

Note: `sampleBezierPath` at line 34 stays `public` — it's the entry point used by InsideMan.

#### 4. Tighten DeviceConnection callback access
**File**: `ButtonHeist/Sources/Wheelman/DeviceConnection.swift`
**Changes**: Change lines 18-24 from `public` to package-level access

Since `DeviceConnection` is only consumed by `HeistClient` within the `ButtonHeist` module (which depends on `Wheelman`), and both are in the same package via local path dependency, we can use `package` access:

```swift
// Before (lines 18-24):
public var onConnected: (() -> Void)?
public var onDisconnected: ((Error?) -> Void)?
public var onServerInfo: ((ServerInfo) -> Void)?
public var onInterface: ((Interface) -> Void)?
public var onActionResult: ((ActionResult) -> Void)?
public var onScreen: ((ScreenPayload) -> Void)?
public var onError: ((String) -> Void)?

// After:
package var onConnected: (() -> Void)?
package var onDisconnected: ((Error?) -> Void)?
package var onServerInfo: ((ServerInfo) -> Void)?
package var onInterface: ((Interface) -> Void)?
package var onActionResult: ((ActionResult) -> Void)?
package var onScreen: ((ScreenPayload) -> Void)?
package var onError: ((String) -> Void)?
```

**Important**: If `package` access doesn't work due to Tuist target boundaries (Tuist generates an Xcode project where Wheelman and ButtonHeist are separate framework targets, not a single SPM package), fall back to keeping them `public`. Verify by building.

### Success Criteria:

#### Automated Verification:
- [ ] All targets build: run all 4 build commands from the pre-commit checklist
- [ ] MCP builds: `cd ButtonHeistMCP && swift build`
- [ ] CLI builds: `cd ButtonHeistCLI && swift build`
- [ ] All tests pass: run all 3 test commands
- [ ] BezierSampler tests still pass (they use `@testable import TheGoods` so `internal` is accessible)

---

## Phase 4: Clean Unused Design Tokens

### Overview
Remove unused design system tokens from Stakeout's Design/ folder.

### Changes Required:

#### 1. Remove unused color tokens
**File**: `Stakeout/Sources/Design/Colors.swift`
**Changes**: Remove 4 unused tokens, keep 3 used ones

```swift
// Before:
extension Color {
    struct Tree {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let rowHover = Color.primary.opacity(0.04)
        static let rowSelected = Color.accentColor.opacity(0.15)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.3)
        static let divider = Color.primary.opacity(0.1)
    }
}

// After:
extension Color {
    struct Tree {
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.3)
    }
}
```

#### 2. Delete entire Typography.swift
**File**: `Stakeout/Sources/Design/Typography.swift`
**Changes**: Delete the file entirely — all 5 `Font.Tree.*` tokens are unused

#### 3. Remove unused spacing token
**File**: `Stakeout/Sources/Design/Spacing.swift`
**Changes**: Remove `rowVerticalPadding` (line 6)

```swift
// Before:
enum TreeSpacing {
    static let rowHeight: CGFloat = 28
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 4
    static let searchHeight: CGFloat = 32
    static let searchHorizontalPadding: CGFloat = 12
    static let unit: CGFloat = 8
}

// After:
enum TreeSpacing {
    static let rowHeight: CGFloat = 28
    static let rowHorizontalPadding: CGFloat = 12
    static let searchHeight: CGFloat = 32
    static let searchHorizontalPadding: CGFloat = 12
    static let unit: CGFloat = 8
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Stakeout builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Stakeout build`

---

## Phase 5: Migrate HeistClient to @Observable

### Overview
Replace `ObservableObject` with `@Observable` macro on `HeistClient`. Update `@StateObject` to `@State` in Stakeout's ContentView.

### Changes Required:

#### 1. Migrate HeistClient class declaration
**File**: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
**Changes**:

Add `import Observation` at the top (after line 4):
```swift
import Observation
```

Change line 10 from:
```swift
public final class HeistClient: ObservableObject {
```
to:
```swift
@Observable
public final class HeistClient {
```

Remove `@Published` from all 7 properties (lines 14-20). Change from:
```swift
@Published public private(set) var discoveredDevices: [DiscoveredDevice] = []
@Published public private(set) var connectedDevice: DiscoveredDevice?
@Published public private(set) var serverInfo: ServerInfo?
@Published public private(set) var currentInterface: Interface?
@Published public private(set) var currentScreen: ScreenPayload?
@Published public private(set) var isDiscovering: Bool = false
@Published public private(set) var connectionState: ConnectionState = .disconnected
```
to:
```swift
public private(set) var discoveredDevices: [DiscoveredDevice] = []
public private(set) var connectedDevice: DiscoveredDevice?
public private(set) var serverInfo: ServerInfo?
public private(set) var currentInterface: Interface?
public private(set) var currentScreen: ScreenPayload?
public private(set) var isDiscovering: Bool = false
public private(set) var connectionState: ConnectionState = .disconnected
```

#### 2. Update Stakeout's ContentView
**File**: `Stakeout/Sources/Views/ContentView.swift`
**Changes**: Change line 5 from:
```swift
@StateObject private var client = HeistClient()
```
to:
```swift
@State private var client = HeistClient()
```

### Success Criteria:

#### Automated Verification:
- [ ] All targets build: run all 4 build commands from the pre-commit checklist
- [ ] Stakeout builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Stakeout build`
- [ ] MCP builds: `cd ButtonHeistMCP && swift build`
- [ ] CLI builds: `cd ButtonHeistCLI && swift build`
- [ ] All tests pass: run all 3 test commands
- [ ] ButtonHeist tests pass (HeistClientTests verifies initial state)

---

## Testing Strategy

### Automated Tests:
- All existing tests must continue to pass — no test changes expected
- `BezierSamplerTests` uses `@testable import` so `internal` access is fine
- `HeistClientTests` tests initial state of properties — works with both `@Published` and `@Observable`
- `DiscoveredDeviceTests` already tests name parsing — the new `matches(filter:)` method uses the same computed properties

### No New Tests Required:
The changes are mechanical refactors (deduplication, dead code removal, macro migration). Existing test coverage validates correctness.

## Performance Considerations

The `@Observable` migration provides a performance improvement: SwiftUI will only re-render views that read the specific property that changed, instead of re-rendering on any `@Published` change. This particularly benefits Stakeout where `currentScreen` changes frequently but only `ScreenshotView` reads it.

## References

- Research document: `thoughts/shared/research/2026-02-19-codebase-architecture-review.md`
- HeistClient: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
- DiscoveredDevice: `ButtonHeist/Sources/Wheelman/DiscoveredDevice.swift`
- DeviceConnector: `ButtonHeistCLI/Sources/DeviceConnector.swift`
- TypeCommand: `ButtonHeistCLI/Sources/TypeCommand.swift`
- CLIRunner: `ButtonHeistCLI/Sources/CLIRunner.swift`
- MCP server: `ButtonHeistMCP/Sources/main.swift`
