# ButtonThief Heist Rebrand Implementation Plan

## Overview

Rebrand the entire Accra project to use a heist film metaphor. The system becomes **ButtonThief** — a toolkit that smuggles out your app's interface information, with a **Conductor** managing the **InsideMan** who cracks open the vault of your app and drives it remotely. We're breaking out the crown jewels of control.

## Current State Analysis

The project currently uses "Accra" as the brand name across 100+ files spanning:
- 5 Swift modules (AccraCore, AccraHost, AccraHostLoader, AccraClient, AccraCLI)
- 1 macOS app (AccraInspector)
- 2 test apps (AccessibilityTestApp, UIKitTestApp)
- Tuist project configuration
- SPM package manifests
- Documentation, scripts, and tests

### Key Discoveries:
- Tuist generates `.xcodeproj`, `.xcworkspace`, and `Derived/` — these don't need manual editing, just regeneration
- The ObjC `+load` bridge uses C ABI function names that must be renamed in both `.m` and `.swift`
- Bundle IDs follow `com.accra.*` pattern consistently
- Info.plist keys use `AccraHost*` prefix
- Environment variables use `ACCRA_HOST_*` prefix
- Bonjour service type is `_a11ybridge._tcp`
- Python USB module defines its own class hierarchy with `Accra*` names

## Desired End State

After this plan is complete:
- All modules, types, files, and directories use the new heist names
- All builds succeed (`ButtonThief`, `Blueprint`, `InsideMan`, `Wheelman`, `Stakeout`)
- All tests pass (`BlueprintTests`, `WheelmanTests`, `ButtonThiefCLITests`)
- Documentation reflects the new branding
- The CLI is invoked as `buttonthief` instead of `accra`
- Bonjour advertises as `_buttonthief._tcp`

## Complete Rename Mapping

| Current | New | Heist Role |
|---|---|---|
| **Accra** (workspace/project) | **ButtonThief** | The operation |
| **AccraCore** (shared types module) | **Blueprint** | The shared heist plans |
| **AccraHost** (iOS server) | **InsideMan** | The planted agent |
| **AccraHostCore** (product, no auto-start) | **InsideManCore** | Manually deployed agent |
| **AccraHostLoader** (ObjC auto-start) | **InsideManLoader** | Auto-infiltration mechanism |
| **AccraClient** (macOS client) | **Wheelman** | The getaway driver |
| **AccraInspector** (macOS GUI) | **Stakeout** | Visual surveillance |
| **AccraCLI** (CLI package) | **ButtonThiefCLI** | Command center |
| `accra` (CLI executable) | `buttonthief` | Command center tool |

### Identifier Mapping

| Current | New |
|---|---|
| `com.accra.core` | `com.buttonthief.blueprint` |
| `com.accra.host` | `com.buttonthief.insideman` |
| `com.accra.client` | `com.buttonthief.wheelman` |
| `com.accra.inspector` | `com.buttonthief.stakeout` |
| `com.accra.core.tests` | `com.buttonthief.blueprint.tests` |
| `com.accra.client.tests` | `com.buttonthief.wheelman.tests` |
| `com.accra.testapp` | `com.buttonthief.testapp` |
| `com.accra.uikittestapp` | `com.buttonthief.uikittestapp` |
| `com.accra.\(name.lowercased())` | `com.buttonthief.\(name.lowercased())` |

### Config Key Mapping

| Current | New |
|---|---|
| `AccraHostPort` | `InsideManPort` |
| `AccraHostDisableAutoStart` | `InsideManDisableAutoStart` |
| `AccraHostPollingInterval` | `InsideManPollingInterval` |
| `ACCRA_HOST_DISABLE` | `INSIDEMAN_DISABLE` |
| `ACCRA_HOST_PORT` | `INSIDEMAN_PORT` |
| `ACCRA_HOST_POLLING_INTERVAL` | `INSIDEMAN_POLLING_INTERVAL` |

### Service/Protocol Mapping

| Current | New |
|---|---|
| `_a11ybridge._tcp` | `_buttonthief._tcp` |
| `accraServiceType` | `buttonThiefServiceType` |
| `[AccraHost]` (log prefix) | `[InsideMan]` |
| `AccraHost_autoStartFromLoad` | `InsideMan_autoStartFromLoad` |
| `accraHostAutoStartFromLoad()` | `insideManAutoStartFromLoad()` |

### Python Module Mapping

| Current | New |
|---|---|
| `accra_usb.py` | `buttonthief_usb.py` |
| `AccraUSBConnection` | `ButtonThiefUSBConnection` |
| `AccraUSBError` | `ButtonThiefUSBError` |
| `from accra_usb import` | `from buttonthief_usb import` |

## What We're NOT Doing

- Not changing the `AccessibilitySnapshot` submodule (external dependency, unchanged)
- Not changing the test app names (`AccessibilityTestApp`, `UIKitTestApp`) — these are targets, not brands
- Not renaming the `TestApp/` directory — it's descriptive, not branded
- Not changing internal type names that don't contain "Accra" (e.g., `DiscoveredDevice`, `ServerInfo`, `ClientMessage`)
- Not modifying internal protocol/message formats — wire compatibility is preserved
- Not renaming the `thoughts/shared/` planning documents (historical records)

## Implementation Approach

The safest approach is: rename directories first, then update all file contents, then regenerate Tuist project files. Since Tuist generates `.xcodeproj`/`.xcworkspace`/`Derived/`, we only need to update Tuist config and regenerate.

---

## Phase 1: Directory and File Renames

### Overview
Rename all directories and files containing "Accra" using `git mv` to preserve history.

### Changes Required:

#### 1. Top-level directory renames
```bash
git mv AccraCore Blueprint
git mv AccraInspector Stakeout
git mv AccraCLI ButtonThiefCLI
```

#### 2. Source directory renames (inside Blueprint, formerly AccraCore)
```bash
git mv Blueprint/Sources/AccraCore Blueprint/Sources/Blueprint
git mv Blueprint/Sources/AccraHost Blueprint/Sources/InsideMan
git mv Blueprint/Sources/AccraHostLoader Blueprint/Sources/InsideManLoader
git mv Blueprint/Sources/AccraClient Blueprint/Sources/Wheelman
git mv Blueprint/Tests/AccraCoreTests Blueprint/Tests/BlueprintTests
git mv Blueprint/Tests/AccraClientTests Blueprint/Tests/WheelmanTests
```

#### 3. Source file renames
```bash
git mv Blueprint/Sources/InsideMan/AccraHost.swift Blueprint/Sources/InsideMan/InsideMan.swift
git mv Blueprint/Sources/Wheelman/AccraClient.swift Blueprint/Sources/Wheelman/Wheelman.swift
git mv Blueprint/Sources/InsideManLoader/AccraHostAutoStart.m Blueprint/Sources/InsideManLoader/InsideManAutoStart.m
git mv Blueprint/Sources/InsideManLoader/include/AccraHostAutoStart.h Blueprint/Sources/InsideManLoader/include/InsideManAutoStart.h
git mv Stakeout/Sources/AccraInspectorApp.swift Stakeout/Sources/StakeoutApp.swift
git mv Stakeout/AccraInspector.entitlements Stakeout/Stakeout.entitlements
```

#### 4. Test file renames
```bash
git mv Blueprint/Tests/BlueprintTests/AccraCoreTests.swift Blueprint/Tests/BlueprintTests/BlueprintTests.swift
git mv Blueprint/Tests/WheelmanTests/AccraClientTests.swift Blueprint/Tests/WheelmanTests/WheelmanTests.swift
git mv Blueprint/Tests/WheelmanTests/AccraClientStateTests.swift Blueprint/Tests/WheelmanTests/WheelmanStateTests.swift
```

#### 5. CLI test file rename
```bash
git mv ButtonThiefCLI/Tests/AccraCLITests.swift ButtonThiefCLI/Tests/ButtonThiefCLITests.swift
```

#### 6. Script rename
```bash
git mv scripts/accra_usb.py scripts/buttonthief_usb.py
```

#### 7. Delete generated artifacts (will be regenerated by Tuist)
```bash
rm -rf Accra.xcworkspace Accra.xcodeproj Derived TestApp/TestApp.xcodeproj
```

### Success Criteria:
- [ ] All `git mv` operations complete without error
- [ ] No files or directories with "Accra" or "accra" in their name remain (except `Accra.xcworkspace/` and `Accra.xcodeproj/` which get deleted)
- [ ] Git tracks all renames correctly: `git status` shows renames

---

## Phase 2: Source Code Content Updates

### Overview
Update all file contents to replace Accra references with the new heist names.

### Changes Required:

#### 1. Blueprint/Sources/Blueprint/Messages.swift (formerly AccraCore)
- `accraServiceType = "_a11ybridge._tcp"` → `buttonThiefServiceType = "_buttonthief._tcp"`

#### 2. Blueprint/Sources/InsideMan/InsideMan.swift (formerly AccraHost.swift)
- `import AccraCore` → `import Blueprint`
- `class AccraHost` → `class InsideMan`
- All `AccraHost` references in the class (`.shared`, `.configure()`, static references)
- `accraServiceType` → `buttonThiefServiceType`
- `serverLog("[AccraHost]..."` → `serverLog("[InsideMan]..."`
- `NSLog("[AccraHost]..."` → `NSLog("[InsideMan]..."`
- `AccraHost_autoStartFromLoad` → `InsideMan_autoStartFromLoad`
- `accraHostAutoStartFromLoad()` → `insideManAutoStartFromLoad()`
- `"ACCRA_HOST_DISABLE"` → `"INSIDEMAN_DISABLE"`
- `"ACCRA_HOST_PORT"` → `"INSIDEMAN_PORT"`
- `"ACCRA_HOST_POLLING_INTERVAL"` → `"INSIDEMAN_POLLING_INTERVAL"`
- `"AccraHostDisableAutoStart"` → `"InsideManDisableAutoStart"`
- `"AccraHostPort"` → `"InsideManPort"`
- `"AccraHostPollingInterval"` → `"InsideManPollingInterval"`
- `"Starting AccraHost..."` → `"Starting InsideMan..."`

#### 3. Blueprint/Sources/InsideMan/SimpleSocketServer.swift
- `com.accra.server.accept` → `com.buttonthief.insideman.accept`
- `com.accra.client.\(clientId)` → `com.buttonthief.insideman.\(clientId)` (these are server-side per-client read queues)

#### 4. Blueprint/Sources/InsideManLoader/InsideManAutoStart.m
- `AccraHost_autoStartFromLoad` → `InsideMan_autoStartFromLoad`
- `AccraHostAutoStart` → `InsideManAutoStart`

#### 5. Blueprint/Sources/InsideManLoader/include/InsideManAutoStart.h (just a comment)
- `// AccraHost auto-initialization support` → `// InsideMan auto-initialization support`

#### 6. Blueprint/Sources/Wheelman/Wheelman.swift (formerly AccraClient.swift)
- `import AccraCore` → `import Blueprint`
- `Logger(subsystem: "com.accra.client"` → `Logger(subsystem: "com.buttonthief.wheelman"`
- `/// A discovered iOS device running AccraHost` → `/// A discovered iOS device running InsideMan`
- `class AccraClient` → `class Wheelman`
- `/// Client for discovering and connecting to iOS apps running AccraHost` → `/// Client for discovering and connecting to iOS apps running InsideMan`

#### 7. Blueprint/Sources/Wheelman/DeviceDiscovery.swift
- `import AccraCore` → `import Blueprint`
- `Logger(subsystem: "com.accra.client"` → `Logger(subsystem: "com.buttonthief.wheelman"`
- `accraServiceType` → `buttonThiefServiceType`

#### 8. Blueprint/Sources/Wheelman/DeviceConnection.swift
- `import AccraCore` → `import Blueprint`
- `com.accra.client.read` → `com.buttonthief.wheelman.read`

#### 9. Stakeout/Sources/StakeoutApp.swift (formerly AccraInspectorApp.swift)
- `struct AccraInspectorApp` → `struct StakeoutApp`

#### 10. Stakeout/Sources/Views/ContentView.swift
- `import AccraClient` → `import Wheelman`
- Any `AccraClient` type references → `Wheelman`

#### 11. All other Stakeout view files
- `import AccraClient` → `import Wheelman` (if present)
- `import AccraCore` → `import Blueprint` (if present)

#### 12. ButtonThiefCLI/Sources/main.swift
- `import AccraCore` → `import Blueprint` (if present)
- `import AccraClient` → `import Wheelman` (if present)
- `struct Accra: AsyncParsableCommand` → `struct ButtonThief: AsyncParsableCommand`
- `commandName: "accra"` → `commandName: "buttonthief"`
- All `AccraHost` references in help text → `InsideMan`
- All `accra` CLI usage examples → `buttonthief`

#### 13. ButtonThiefCLI/Sources/CLIRunner.swift
- `import AccraClient` → `import Wheelman`
- `import AccraCore` → `import Blueprint` (if present)
- `AccraClient()` → `Wheelman()`

#### 14. ButtonThiefCLI/Sources/ActionCommand.swift
- `import AccraCore` → `import Blueprint`
- `import AccraClient` → `import Wheelman`

#### 15. ButtonThiefCLI/Sources/ScreenshotCommand.swift
- `import AccraCore` → `import Blueprint` (if present)
- `import AccraClient` → `import Wheelman` (if present)

#### 16. All test files in Blueprint/Tests/
- `import AccraCore` → `import Blueprint`
- `@testable import AccraClient` → `@testable import Wheelman`
- `@testable import AccraCore` → `@testable import Blueprint`
- `AccraClient()` → `Wheelman()`
- Test class names containing `Accra` → new names (e.g., `AccraClientStateTests` → `WheelmanStateTests`)

#### 17. All test files in ButtonThiefCLI/Tests/
- `import AccraCore` → `import Blueprint`
- Any test class names containing `Accra`

#### 18. TestApp/Sources/AccessibilityTestApp.swift
- `import AccraHost` → `import InsideMan`
- `import AccraCore` → `import Blueprint` (if present)
- Comment: `AccraHost auto-starts` → `InsideMan auto-starts`

#### 19. TestApp/UIKitSources/AppDelegate.swift
- `import AccraHost` → `import InsideMan`
- Comment: `AccraHost auto-starts` → `InsideMan auto-starts`

#### 20. scripts/buttonthief_usb.py (formerly accra_usb.py)
- `AccraUSBConnection` → `ButtonThiefUSBConnection`
- `AccraUSBError` → `ButtonThiefUSBError`
- `DeviceNotFoundError(AccraUSBError)` → `DeviceNotFoundError(ButtonThiefUSBError)`
- `ConnectionError(AccraUSBError)` → `ConnectionError(ButtonThiefUSBError)`
- `from accra_usb import` → `from buttonthief_usb import`
- `com.accra.testapp` → `com.buttonthief.testapp`
- `AccraHost` references in docstrings → `InsideMan`
- `"Accra USB Connection"` → `"ButtonThief USB Connection"`
- `"Connecting to AccraHost"` → `"Connecting to InsideMan"`

#### 21. scripts/usb-connect.sh
- `com.accra.testapp` → `com.buttonthief.testapp`
- `AccraHost` → `InsideMan`
- `Accra USB Connection` → `ButtonThief USB Connection`
- `AccraHost` in comments → `InsideMan`

### Success Criteria:
- [ ] No source file contains the string "Accra" or "accra" (except in historical comments if any)
- [ ] All import statements reference new module names
- [ ] All type names use new naming convention
- [ ] `grep -ri "accra" --include="*.swift" --include="*.m" --include="*.h" --include="*.py" --include="*.sh"` returns no results from source files

---

## Phase 3: Package Manifest Updates

### Overview
Update both SPM Package.swift files with new names, paths, and product definitions.

### Changes Required:

#### 1. Blueprint/Package.swift (formerly AccraCore/Package.swift)
```swift
let package = Package(
    name: "Blueprint",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Blueprint", targets: ["Blueprint"]),
        .library(name: "InsideMan", targets: ["InsideMan", "InsideManLoader"]),
        .library(name: "InsideManCore", targets: ["InsideMan"]),
        .library(name: "Wheelman", targets: ["Wheelman"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(name: "Blueprint", path: "Sources/Blueprint"),
        .target(
            name: "InsideMan",
            dependencies: [
                "Blueprint",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/InsideMan"
        ),
        .target(
            name: "InsideManLoader",
            dependencies: ["InsideMan"],
            path: "Sources/InsideManLoader",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Wheelman",
            dependencies: ["Blueprint"],
            path: "Sources/Wheelman"
        ),
        .testTarget(
            name: "BlueprintTests",
            dependencies: ["Blueprint"],
            path: "Tests/BlueprintTests"
        )
    ]
)
```

#### 2. ButtonThiefCLI/Package.swift (formerly AccraCLI/Package.swift)
```swift
let package = Package(
    name: "ButtonThiefCLI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Blueprint"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "buttonthief",
            dependencies: [
                .product(name: "Blueprint", package: "Blueprint"),
                .product(name: "Wheelman", package: "Blueprint"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "ButtonThiefCLITests",
            dependencies: [
                .product(name: "Blueprint", package: "Blueprint")
            ],
            path: "Tests"
        )
    ]
)
```

### Success Criteria:
- [ ] `swift package dump-package` works in both `Blueprint/` and `ButtonThiefCLI/`
- [ ] Product and target names are consistent with the rename mapping

---

## Phase 4: Tuist Configuration Updates

### Overview
Update all Tuist project files to use the new names, then regenerate.

### Changes Required:

#### 1. Workspace.swift
```swift
let workspace = Workspace(
    name: "ButtonThief",
    projects: [".", "TestApp"]
)
```

#### 2. Project.swift
Update all target names, bundle IDs, source paths, dependency references, scheme names, and user-facing strings:
- Project name: `"Accra"` → `"ButtonThief"`
- Target `"AccraCore"` → `"Blueprint"` with sources `"Blueprint/Sources/Blueprint/**"`
- Target `"AccraHost"` → `"InsideMan"` with sources from `"Blueprint/Sources/InsideMan/**"` and `"Blueprint/Sources/InsideManLoader/**"`
- Headers path: `"Blueprint/Sources/InsideManLoader/include/**"`
- Target `"AccraClient"` → `"Wheelman"` with sources `"Blueprint/Sources/Wheelman/**"`
- Target `"AccraInspector"` → `"Stakeout"` with sources `"Stakeout/Sources/**"`
- Entitlements: `"Stakeout/Stakeout.entitlements"`
- Bundle IDs: all `com.accra.*` → `com.buttonthief.*`
- `CFBundleDisplayName`: `"Accra Inspector"` → `"Stakeout"`
- `NSLocalNetworkUsageDescription`: update to reference InsideMan
- `NSBonjourServices`: `["_a11ybridge._tcp"]` → `["_buttonthief._tcp"]`
- Test targets: `"AccraCoreTests"` → `"BlueprintTests"`, `"AccraClientTests"` → `"WheelmanTests"`
- Test sources: updated paths under `Blueprint/Tests/`
- All dependency references updated
- Scheme names updated

#### 3. TestApp/Project.swift
- Bundle IDs: `com.accra.testapp` → `com.buttonthief.testapp`, `com.accra.uikittestapp` → `com.buttonthief.uikittestapp`
- `NSBonjourServices`: `["_a11ybridge._tcp"]` → `["_buttonthief._tcp"]`
- Dependencies: `.project(target: "AccraCore", path: "..")` → `.project(target: "Blueprint", path: "..")`
- Dependencies: `.project(target: "AccraHost", path: "..")` → `.project(target: "InsideMan", path: "..")`

#### 4. Tuist/ProjectDescriptionHelpers/Project+Templates.swift
- `com.accra.\(name.lowercased())` → `com.buttonthief.\(name.lowercased())`

#### 5. Regenerate Tuist project
```bash
tuist generate
```

### Success Criteria:
- [ ] `tuist generate` completes without errors
- [ ] Generated `ButtonThief.xcworkspace` exists
- [ ] Generated `ButtonThief.xcodeproj` exists

---

## Phase 5: Build Verification

### Overview
Verify all targets build successfully with the new names.

### Automated Verification:
- [ ] Core framework builds: `xcodebuild -workspace ButtonThief.xcworkspace -scheme Blueprint build`
- [ ] Host framework builds: `xcodebuild -workspace ButtonThief.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [ ] Client framework builds: `xcodebuild -workspace ButtonThief.xcworkspace -scheme Wheelman build`
- [ ] Inspector app builds: `xcodebuild -workspace ButtonThief.xcworkspace -scheme Stakeout build`
- [ ] CLI builds: `cd ButtonThiefCLI && swift build`

**Implementation Note**: If builds fail, fix issues before proceeding. Common issues will be missed renames in source files.

---

## Phase 6: Test Verification

### Overview
Run all test suites to verify nothing is broken.

### Automated Verification:
- [ ] Core tests pass: `xcodebuild -workspace ButtonThief.xcworkspace -scheme BlueprintTests test`
- [ ] Client tests pass: `xcodebuild -workspace ButtonThief.xcworkspace -scheme WheelmanTests test`
- [ ] CLI tests pass: `cd ButtonThiefCLI && swift test`

---

## Phase 7: Documentation Updates

### Overview
Update all documentation files to reflect the new branding.

### Changes Required:

#### 1. README.md
- Replace all "Accra" references with appropriate new names
- Update build commands, CLI examples, and feature descriptions
- Update component names in architecture descriptions

#### 2. CLAUDE.md
- Update build commands: `AccraCore` → `Blueprint`, `AccraHost` → `InsideMan`, `AccraClient` → `Wheelman`
- Update workspace name: `Accra.xcworkspace` → `ButtonThief.xcworkspace`
- Update scheme names in all `xcodebuild` commands
- Update test scheme names

#### 3. docs/API.md
- Update module names, type names, CLI examples

#### 4. docs/ARCHITECTURE.md
- Update component names and descriptions

#### 5. docs/WIRE-PROTOCOL.md
- Update service type: `_a11ybridge._tcp` → `_buttonthief._tcp`
- Update any AccraHost/AccraClient references

#### 6. docs/USB_DEVICE_CONNECTIVITY.md
- Update AccraHost/AccraClient references
- Update bundle ID references
- Update script names

#### 7. docs/DESIGN-SYSTEM.md
- Update any AccraInspector references → Stakeout

#### 8. CHANGELOG.md
- Add entry for the rebrand
- Update historical references where they'd be confusing

#### 9. CONTRIBUTING.md
- Update build instructions and naming references

### Success Criteria:
- [ ] `grep -ri "accra" *.md docs/*.md` returns no results (except possibly CHANGELOG historical notes)
- [ ] All code examples in docs use new names
- [ ] All `xcodebuild` commands in CLAUDE.md are correct

---

## Phase 8: Final Audit

### Overview
Comprehensive sweep to catch any remaining Accra references.

### Automated Verification:
- [ ] Full grep audit: `grep -ri "accra" --include="*.swift" --include="*.m" --include="*.h" --include="*.py" --include="*.sh" --include="*.md" --include="*.swift"` returns no unexpected results
- [ ] All builds still pass after documentation changes
- [ ] All tests still pass
- [ ] CLI help text shows `buttonthief` not `accra`: `cd ButtonThiefCLI && swift run buttonthief --help`

---

## Testing Strategy

### Automated Tests:
- All existing unit tests renamed and passing (BlueprintTests, WheelmanTests, ButtonThiefCLITests)
- Build verification for all 5 main targets
- CLI executable produces correct output

### Integration Test:
- CLI `buttonthief --help` shows correct branding
- Bonjour service type advertised correctly (verify in source code)

## Performance Considerations

None — this is a pure rename with no behavioral changes.

## Migration Notes

- This is a breaking change for anyone importing the old module names
- The wire protocol format is unchanged — only the Bonjour service name changes
- Old `_a11ybridge._tcp` services won't be discovered by new clients
- Info.plist keys change from `AccraHost*` to `InsideMan*`
- Environment variables change from `ACCRA_HOST_*` to `INSIDEMAN_*`

## References

- Current codebase: all files under `/Users/aodawa/conductor/workspaces/accra/colombo/`
- Key config files: `Project.swift`, `Workspace.swift`, `Blueprint/Package.swift`, `ButtonThiefCLI/Package.swift`
