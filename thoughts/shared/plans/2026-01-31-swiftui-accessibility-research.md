# SwiftUI Accessibility Hierarchy Research Plan

## Overview

This document outlines a research plan for discovering how to access the iOS accessibility hierarchy from SwiftUI lifecycle apps (`@main App`) without UIKit view injection. The goal is to enable [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) to support pure SwiftUI apps.

## Problem Statement

AccessibilitySnapshot currently requires a `UIView` as the root for accessibility hierarchy traversal:

```swift
// Current approach (AccessibilityHierarchyParser.swift:266)
let accessibilityNodes = root.recursiveAccessibilityHierarchy()
```

For SwiftUI views within UIKit apps, this works via `UIHostingController.view`. However, pure SwiftUI lifecycle apps (`@main struct MyApp: App`) abstract away the underlying `UIWindow` and `UIHostingController`, requiring a different approach.

## Current State Analysis

### How AccessibilitySnapshot Works Today

1. **Accessibility Enablement** (`ASAccessibilityEnabler.m:26-30`):
   ```objc
   void *handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LOCAL);
   int (*_AXSAutomationEnabled)(void) = dlsym(handle, "_AXSAutomationEnabled");
   void (*_AXSSetAutomationEnabled)(int) = dlsym(handle, "_AXSSetAutomationEnabled");
   _AXSSetAutomationEnabled(YES);
   ```
   Uses private `libAccessibility.dylib` functions to enable accessibility without VoiceOver running.

2. **Hierarchy Traversal** (`AccessibilityHierarchyParser.swift:678-743`):
   - Starts from a `UIView` root
   - Recursively walks `subviews` and `accessibilityElements`
   - Uses public UIAccessibility APIs: `isAccessibilityElement`, `accessibilityElements`, `accessibilityLabel`, etc.
   - Private API usage limited to trait detection and UITabBar internals

3. **SwiftUI Support** (current, limited):
   - Wraps SwiftUI view in `UIHostingController`
   - Uses `hostingController.view` as the traversal root
   - Works only when you control the hosting controller creation

### Key Discoveries from Research

1. **SwiftUI apps still use UIKit infrastructure**: `UIWindow`, `UIScene`, `UIHostingController` exist under the hood
2. **`_UIHostingView`**: Private UIView subclass at the root of SwiftUI hierarchy
3. **No public API** for runtime accessibility tree introspection (confirmed via Swift Forums)
4. **`AXRuntime.framework`**: Private framework with `AXElement`, `AXUIElement` classes for accessibility traversal
5. **Existing libraries** like `swiftui-introspect` successfully access underlying UIKit views without private APIs

## Research Phases

---

## Phase 1: UIWindow/UIScene Access from SwiftUI Apps

### Objective
Find reliable methods to access the underlying `UIWindow` from a pure SwiftUI lifecycle app.

### Research Tasks

#### 1.1 UIApplication.shared.connectedScenes Approach
**Hypothesis**: Can traverse `connectedScenes` to find `UIWindow`.

```swift
// Experimental code to validate
if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
   let window = windowScene.windows.first {
    // window.rootViewController?.view is the root
}
```

**Test**: Create a SwiftUI app, call this code in `.onAppear`, verify access to the view hierarchy.

**Success Criteria**:
- [ ] Can access `UIWindow` from SwiftUI `@main App`
- [ ] Can access root `UIView` containing SwiftUI content
- [ ] Works without any UIKit setup code

#### 1.2 UIViewRepresentable Injection
**Hypothesis**: Inject an invisible `UIViewRepresentable` that captures its hosting window.

```swift
struct WindowAccessor: UIViewRepresentable {
    @Binding var window: UIWindow?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }
}
```

**Test**: Add this to a SwiftUI view, verify `window` binding is populated.

**Success Criteria**:
- [ ] Window is accessible after view appears
- [ ] Can traverse from window to full accessibility hierarchy

#### 1.3 Evaluate Existing Libraries
**Libraries to Examine**:
- [SwiftUIWindowBinder](https://github.com/happycodelucky/SwiftUIWindowBinder)
- [WindowKit](https://github.com/divadretlaw/WindowKit)
- [swiftui-introspect](https://github.com/siteline/swiftui-introspect)

**Goal**: Understand their window access patterns, evaluate for integration.

### Deliverables
- Working proof-of-concept for window access
- Documented API for accessing root view from SwiftUI App

---

## Phase 2: Private Framework Exploration

### Objective
Investigate iOS private frameworks for direct accessibility hierarchy access, bypassing the need for a UIView root.

### Research Tasks

#### 2.1 AXRuntime.framework Analysis
**Source**: Headers at [iOS-Runtime-Headers](https://github.com/nst/iOS-Runtime-Headers/tree/master/PrivateFrameworks/AXRuntime.framework)

**Key Classes to Investigate**:
- `AXElement` - Primary accessible element representation
- `AXUIElement` - UIKit-specific wrapper
- `AXElementFetcher` - Retrieves elements from hierarchy
- `AXRemoteElement` - Cross-process element access

**Method to Extract**:
```bash
# On macOS with iOS Simulator runtime
class-dump /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime
```

**Questions to Answer**:
- Can we instantiate `AXElement` for the current app?
- Does `AXUIElement.uiElementAtCoordinate:forApplication:contextId:` work in-process?
- Can we get the root accessibility element without a UIView?

#### 2.2 libAccessibility.dylib Deep Dive
**Currently Used Functions**:
- `_AXSAutomationEnabled()`
- `_AXSSetAutomationEnabled()`

**Potential Additional Functions** (to discover via disassembly):
- Functions to enumerate accessibility elements
- Functions to get the root element
- Functions to traverse the hierarchy

**Tool**: Hopper Disassembler or Ghidra on `/usr/lib/libAccessibility.dylib` from Simulator runtime.

#### 2.3 UIAccessibility Private Headers
**Investigation Target**: Private methods on `NSObject`/`UIView` related to accessibility.

**Method**: Use `class-dump` on UIKit framework, grep for accessibility-related selectors.

```bash
class-dump UIKit.framework | grep -i accessibility
```

### Deliverables
- Documented private API options with risk assessment
- Proof-of-concept using private APIs (if viable)

---

## Phase 3: SwiftUI Internal Architecture

### Objective
Understand how SwiftUI constructs and manages accessibility elements internally.

### Research Tasks

#### 3.1 SwiftUI Accessibility Representation
**Hypothesis**: SwiftUI generates `UIAccessibilityElement` instances internally.

**Investigation Approach**:
1. Create a SwiftUI view with accessibility modifiers
2. Use Frida or lldb to inspect the view hierarchy at runtime
3. Find where accessibility elements are created

```swift
Text("Hello")
    .accessibilityLabel("Greeting")
    .accessibilityHint("A greeting message")
```

**Questions**:
- Are these stored as `UIAccessibilityElement` instances?
- Where in the hierarchy do they live?
- Can we access them without the hosting UIView?

#### 3.2 _UIHostingView Analysis
**Private Class**: `_UIHostingView<Content>` is the UIView subclass backing SwiftUI content.

**Investigation**:
1. Get class dump of `_UIHostingView`
2. Find accessibility-related methods
3. Understand how it bridges SwiftUI accessibility to UIAccessibility

```bash
# Runtime inspection
(lldb) po [UIHostingController alloc]
(lldb) expression -l objc -O -- [_UIHostingView _shortMethodDescription]
```

#### 3.3 SwiftUI Accessibility Internals via Reflection
**Tool**: ViewInspector library or Swift Mirror API

**Goal**: Understand if SwiftUI's internal view representation includes accessibility data we can extract.

### Deliverables
- Documentation of SwiftUI's internal accessibility architecture
- Potential hooks for extraction

---

## Phase 4: Alternative Approaches

### Objective
Explore unconventional methods that might provide accessibility hierarchy access.

### Research Tasks

#### 4.1 XCTest / XCUITest Framework Approach
**Observation**: UI tests can access accessibility elements. How?

**Investigation**:
- Examine `XCUIElement` and `XCUIElementQuery` internals
- Understand the IPC mechanism between test runner and app
- Determine if we can use similar mechanisms

**Note**: XCUITest runs out-of-process, so the mechanism differs from in-process access.

#### 4.2 Accessibility Inspector Communication
**Hypothesis**: Accessibility Inspector communicates with apps via some IPC mechanism.

**Investigation**:
- Use `dtrace` or Frida to monitor IPC when Accessibility Inspector connects
- Identify the protocol/service used
- Determine if we can replicate this in-app

#### 4.3 VoiceOver's Internal Mechanism
**Hypothesis**: VoiceOver queries apps for accessibility elements via a specific API.

**Investigation**:
- Monitor with Frida when VoiceOver activates
- Identify callbacks/queries the app receives
- Explore if we can trigger these programmatically

### Deliverables
- Assessment of alternative approaches viability
- Proof-of-concept for most promising approach

---

## Phase 5: Solution Design & Implementation

### Objective
Based on research findings, design and implement a solution for SwiftUI accessibility snapshot support.

### Potential Solution Architectures

#### Option A: UIWindow Access (Recommended Starting Point)
**Approach**: Access `UIWindow` from SwiftUI app, use existing traversal logic.

**Pros**:
- Minimal changes to existing codebase
- Uses public APIs
- Reliable

**Cons**:
- Requires view to be in window
- May miss some SwiftUI-specific accessibility data

#### Option B: Private AXRuntime APIs
**Approach**: Use `AXElement`/`AXUIElement` to traverse hierarchy directly.

**Pros**:
- Direct access to system's accessibility tree
- Potentially more accurate to VoiceOver's view

**Cons**:
- Private API, may break between iOS versions
- App Store rejection risk (acceptable for testing tools)

#### Option C: Hybrid Approach
**Approach**: Combine UIWindow access with AXRuntime queries for verification.

**Pros**:
- Redundancy and verification
- Best accuracy

**Cons**:
- Most complex implementation

### Implementation Tasks

1. [ ] Create experimental branch for solution development
2. [ ] Implement window access helper for SwiftUI apps
3. [ ] Add SwiftUI lifecycle app test case
4. [ ] Validate accessibility traversal works correctly
5. [ ] Document SwiftUI-specific considerations
6. [ ] Submit PR to AccessibilitySnapshot

### Deliverables
- Working SwiftUI lifecycle app support
- Updated documentation
- Test cases demonstrating functionality

---

## Target iOS Version

**iOS 18+ only** - This simplifies our approach:
- Can use latest SwiftUI/UIKit APIs without version checks
- Private API surface is more stable (single major version)
- No need for backwards-compatible fallback code
- Can leverage iOS 18 accessibility improvements

## Success Criteria (Overall)

### Automated Verification
- [ ] Can create accessibility snapshot from `@main struct App: App` without `UIHostingController`
- [ ] Traversal finds all accessibility elements in SwiftUI hierarchy
- [ ] Coordinates and shapes are correctly mapped
- [ ] Existing UIKit tests continue to pass

### Manual Verification
- [ ] Snapshot output matches VoiceOver's navigation order
- [ ] All accessibility properties (label, value, traits, hints) captured
- [ ] Custom actions and rotors work correctly
- [ ] Works on iOS 18+

---

## Tools Needed

### Development
- Xcode 15+ with iOS 17+ SDK
- iOS Simulator (multiple versions for testing)
- Physical device (for VoiceOver verification)

### Reverse Engineering
- **Hopper Disassembler** or **Ghidra** - For analyzing private frameworks
- **class-dump** or **dsdump** - For extracting Objective-C headers
- **Frida** - For runtime inspection and hooking
- **lldb** - For debugging and runtime exploration

### Resources
- [iOS-Runtime-Headers](https://github.com/nst/iOS-Runtime-Headers) - Private framework headers
- [The iPhone Wiki](https://www.theiphonewiki.com/) - iOS internals documentation
- WWDC Sessions on SwiftUI and Accessibility

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Private APIs break in new iOS | High | Medium | Version-specific implementations, runtime checks |
| App Store rejection | N/A | N/A | Testing tool, not for App Store |
| SwiftUI internals change | Medium | High | Abstract implementation, version detection |
| Performance overhead | Low | Low | Lazy evaluation, caching |
| Incomplete coverage | Medium | Medium | Validate against VoiceOver behavior |

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: UIWindow Access | 2-3 days | None |
| Phase 2: Private Framework | 3-5 days | class-dump, Hopper |
| Phase 3: SwiftUI Internals | 3-4 days | Phase 1, Frida |
| Phase 4: Alternatives | 2-3 days | Phase 2 |
| Phase 5: Implementation | 5-7 days | Phases 1-4 |

**Total**: ~3-4 weeks for comprehensive research and initial implementation

---

## References

- [AccessibilitySnapshot Source](https://github.com/cashapp/AccessibilitySnapshot)
- [iOS-Runtime-Headers: AXRuntime](https://github.com/nst/iOS-Runtime-Headers/tree/master/PrivateFrameworks/AXRuntime.framework)
- [swiftui-introspect](https://github.com/siteline/swiftui-introspect) - Reference for accessing UIKit from SwiftUI
- [Swift Forums: Accessibility Tree Introspection](https://forums.swift.org/t/is-it-possible-to-dump-introspect-my-own-accessibility-tree-at-runtime-swiftui/83728)
- [WWDC21: SwiftUI Accessibility Beyond Basics](https://developer.apple.com/videos/play/wwdc2021/10119/)

---

## Next Steps

1. **Immediate**: Set up test app to validate Phase 1 approaches
2. **This Week**: Complete Phase 1 research and document findings
3. **Following**: Begin Phase 2 private framework exploration in parallel
