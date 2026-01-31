# SwiftUI Accessibility Hierarchy - Research Insights

**Date:** 2026-01-31
**Target:** iOS 18+
**Goal:** Enable AccessibilitySnapshot for pure SwiftUI lifecycle apps

---

## Executive Summary

**Finding:** No new private APIs are needed. The existing `AccessibilityHierarchyParser` works for SwiftUI lifecycle apps. The only missing piece is getting the root `UIView` from the app's window.

---

## How AccessibilitySnapshot Works Today

### For UIKit Apps
```swift
// Direct - you have the UIView
let parser = AccessibilityHierarchyParser()
let markers = parser.parseAccessibilityElements(in: myUIView)
```

### For SwiftUI Views (in tests)
```swift
// Wraps SwiftUI view in UIHostingController
SnapshotVerifyAccessibility(SwiftUIView(), size: screenSize)

// Internally does:
let hostingController = UIHostingController(rootView: swiftUIView)
let uiView = hostingController.view  // _UIHostingView
parser.parseAccessibilityElements(in: uiView)
```

### The Gap: SwiftUI Lifecycle Apps
```swift
@main
struct MyApp: App {  // No UIHostingController to access
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

## Key Discovery: Window Access Pattern

SwiftUI lifecycle apps **do** have a `UIHostingController` - the system creates it. Access it via:

```swift
guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      let rootView = window.rootViewController?.view else { return }

// rootView is _UIHostingView<ModifiedContent<AnyView, RootModifier>>
// This is the SAME type as UIHostingController(rootView:).view
```

### Verified Output
```
Window: <UIWindow: 0x105d15db0; frame = (0 0; 402 874); ...>
Root VC: UIHostingController<ModifiedContent<AnyView, RootModifier>>
Root View Type: _UIHostingView<ModifiedContent<AnyView, RootModifier>>
```

---

## How the Parser Traverses the Hierarchy

### Entry Point
```swift
root.recursiveAccessibilityHierarchy()
```

### Three-Way Branch (NSObject extension)
```swift
if isAccessibilityElement {
    // LEAF: This is a focusable element
    return [.element(self)]
}
else if let accessibilityElements = accessibilityElements as? [NSObject] {
    // CONTAINER: Has explicit accessibility children
    return elements.flatMap { $0.recursiveAccessibilityHierarchy() }
}
else if let self = self as? UIView {
    // VIEW: Recurse into subviews
    return subviews.flatMap { $0.recursiveAccessibilityHierarchy() }
}
```

### SwiftUI's Implementation
`_UIHostingView` implements UIAccessibility protocols:
- `isAccessibilityElement` → `false` (it's a container)
- `accessibilityElementCount()` → returns count of SwiftUI elements
- `accessibilityElement(at:)` → returns `SwiftUI.AccessibilityNode`

The `AccessibilityNode` objects have:
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityHint`
- `accessibilityTraits`
- `accessibilityFrame`
- `accessibilityIdentifier`

---

## Private API Exploration Results

### What We Tried

| API | Result | Notes |
|-----|--------|-------|
| AXRuntime.framework | ✅ Loads | dlopen works |
| AXUIElement class | ✅ Available | Can get system-wide element |
| AXElement class | ✅ Available | But init methods limited |
| AXElementFetcher | ✅ Available | Requires complex init |
| `_AXSAXInspectorSetEnabled` | ✅ Works | Enables inspector mode |
| `systemWideAXUIElement` | ✅ Returns element | pid=0, system-wide |
| `uiSystemWideApplication` | ✅ Returns element | AXUIElement |
| `currentApplication` | ❌ nil | Only works externally |
| `_accessibilityUserTestingChildren` | ✅ Works | Returns same as public API |

### Conclusion
The private APIs provide no additional access beyond what the public UIAccessibility APIs already offer. The public APIs are sufficient.

---

## Deep Dive: AXRuntime Framework Classes

Using runtime class introspection, we analyzed 656 AX-prefixed classes in AXRuntime. Key classes for accessibility hierarchy access:

### AXUIElement (76 instance methods, 18 class methods)
Low-level wrapper around `__AXUIElement` C struct. Key APIs:
```
Class Methods:
+ systemWideAXUIElement              → System-wide element (pid=0)
+ uiSystemWideApplication           → AXUIElement for system
+ uiElementAtCoordinate:            → Hit testing
+ uiApplicationWithPid:             → Get app element by PID

Instance Methods:
- pid                               → Process ID
- children                          → Child elements
- initWithAXElement:cache:          → Initialize with caching
- performAXAction:withValue:        → Execute actions
```

### AXElement (253 instance methods, 120 properties)
Higher-level accessibility element abstraction. Key APIs:
```
Properties:
- children: NSArray               → Child accessibility elements
- frame: CGRect                   → Element frame
- label: NSString                 → Accessibility label
- value: NSString                 → Accessibility value
- hint: NSString                  → Accessibility hint
- traits: UInt64                  → Accessibility traits
- parent: NSArray                 → Parent element(s)
- isAccessibleElement: Bool       → Is focusable
- isVisible: Bool                 → Is visible
- currentApplication: AXElement   → Current app element
- firstResponder: AXElement       → First responder

Class Methods:
+ systemWideElement               → System-wide element
+ systemApplication               → System app element
+ elementAtCoordinate:...         → Hit testing
+ currentApplication             → ❌ Returns nil (external only)
```

### AXElementFetcher (132 instance methods, 35 properties)
Fetches accessibility elements from apps:
```
Properties:
- availableElements: NSArray      → All available elements
- elementCache: NSArray           → Cached elements
- rootGroup: AXElementGroup       → Root element group
- nativeFocusElement: AXElement   → Currently focused element

Instance Methods:
- initWithDelegate:fetchEvents:enableEventManagement:
    enableGrouping:shouldIncludeNonScannerElements:beginEnabled:
- refresh                         → Refresh element cache
- firstElement / lastElement      → Navigation
- closestElementToPoint:          → Hit testing

Class Methods:
+ systemWideElement              → System-wide element
+ springBoardElement             → SpringBoard element
```

### AXSimpleRuntimeManager (Singleton)
Runtime management with callbacks:
```
+ sharedManager                   → Singleton instance
- start                           → Start the runtime
- attributeCallback               → Callback for attribute queries
- hitTestCallback                 → Callback for hit testing
- performActionCallback           → Callback for actions
```

### AXRemoteElement (59 instance methods)
Cross-process accessibility elements:
```
- initWithUUID:andRemotePid:andContextId:
- accessibilityElements           → Remote children
- accessibilityFrame              → Frame across processes

Class Methods:
+ registerRemoteElement:remotePort:
+ remoteElementsForContextId:
```

### Why Private APIs Don't Help Our Use Case

1. **AXElement.currentApplication returns nil in-process** - It's designed for external accessibility clients (VoiceOver, etc.)

2. **AXElementFetcher is for assistive technologies** - It monitors system-wide accessibility events, not for in-app use

3. **AXRemoteElement is for cross-process** - Designed for communicating accessibility across process boundaries

4. **Public UIAccessibility APIs are sufficient** - The existing traversal via `isAccessibilityElement`, `accessibilityElements`, and `accessibilityElementCount()` already provides full access to the SwiftUI accessibility tree

---

## SwiftUI.AccessibilityNode Class Dump

From runtime introspection of `SwiftUI.AccessibilityNode`:

```
Inheritance: UIResponder → NSObject

Protocols (3):
- AXChart
- UIAccessibilityContainerDataTable
- UIAccessibilityContainerDataTableCell

Instance Variables (15):
- children           → Child nodes
- parent             → Parent node
- environment        → SwiftUI environment
- source             → Source data
- viewRendererHost   → View renderer
- bridgedChild       → Bridged child node
- ...

Instance Methods (125+):
- accessibilityLabel
- accessibilityValue
- accessibilityHint
- accessibilityTraits
- accessibilityFrame
- accessibilityIdentifier
- accessibilityActivationPoint
- accessibilityCustomActions
- accessibilityCustomContent
- ...
```

This confirms that `SwiftUI.AccessibilityNode` implements all standard UIAccessibility protocols, making it fully compatible with the existing `AccessibilityHierarchyParser`.

---

## Recommended Changes to AccessibilitySnapshot

### Option 1: Add Convenience Method
```swift
extension AccessibilityHierarchyParser {
    /// Get root view from a SwiftUI lifecycle app
    static func getRootViewFromSwiftUIApp() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                  .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootView = window.rootViewController?.view else {
            return nil
        }
        return rootView
    }
}
```

### Option 2: Add Scene-Based Snapshot API
```swift
extension AccessibilitySnapshotView {
    /// Create snapshot from the current app's key window
    convenience init(fromKeyWindow snapshotConfiguration: AccessibilitySnapshotConfiguration) {
        guard let rootView = AccessibilityHierarchyParser.getRootViewFromSwiftUIApp() else {
            fatalError("No key window available")
        }
        self.init(containedView: rootView, snapshotConfiguration: snapshotConfiguration)
    }
}
```

### Option 3: SwiftUI View Extension
```swift
extension View {
    /// Parse accessibility hierarchy of the current app window
    func parseAppAccessibility() -> [AccessibilityMarker] {
        guard let rootView = AccessibilityHierarchyParser.getRootViewFromSwiftUIApp() else {
            return []
        }
        let parser = AccessibilityHierarchyParser()
        return parser.parseAccessibilityElements(in: rootView)
    }
}
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI Lifecycle App                     │
│  @main struct App: App { WindowGroup { ContentView() } }    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      UIWindowScene                           │
│  UIApplication.shared.connectedScenes.first                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        UIWindow                              │
│  windowScene.windows.first                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│    UIHostingController<ModifiedContent<AnyView, ...>>       │
│  window.rootViewController                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│      _UIHostingView<ModifiedContent<AnyView, ...>>          │
│  rootViewController.view                                    │
│                                                             │
│  Implements UIAccessibility:                                │
│  - accessibilityElementCount() → Int                        │
│  - accessibilityElement(at:) → SwiftUI.AccessibilityNode    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              AccessibilityHierarchyParser                    │
│  parseAccessibilityElements(in: _UIHostingView)             │
│                                                             │
│  Traverses via recursiveAccessibilityHierarchy()            │
│  Returns [AccessibilityMarker]                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Test App Code Reference

See `test-aoo/` for working implementation:
- `test_aooApp.swift` - Auto-runs exploration on launch
- `ContentView.swift` - UI with parser and private API buttons
- `PrivateAccessibilityExplorer.swift` - Private API exploration code

---

## Open Questions for Further Research

1. **Complex Hierarchies**: How does the parser handle:
   - `NavigationStack` / `NavigationSplitView`
   - `TabView`
   - `List` with sections
   - `LazyVStack` / `LazyHStack`
   - Modal presentations (`.sheet`, `.fullScreenCover`)

2. **Accessibility Containers**: Do SwiftUI's accessibility containers work correctly?
   - `.accessibilityElement(children: .combine)`
   - `.accessibilityElement(children: .contain)`
   - Custom `AccessibilityRotor`

3. **Dynamic Content**: How does the parser handle:
   - Views that change during parsing
   - Async-loaded content
   - Animations in progress

4. **Multi-Window**: iPad multi-window scenarios - which scene/window to use?

---

## Final Conclusions

### Key Finding
**No private APIs are needed.** The solution is straightforward:

1. SwiftUI lifecycle apps DO create a `UIHostingController` internally
2. Access it via `UIApplication.shared.connectedScenes` → `UIWindowScene` → `UIWindow` → `rootViewController.view`
3. The resulting `_UIHostingView` implements UIAccessibility protocols
4. The existing `AccessibilityHierarchyParser` can traverse it without modification

### What Private API Research Revealed

After extensive exploration of AXRuntime.framework (656 classes, including detailed analysis of AXUIElement, AXElement, AXElementFetcher, AXSimpleRuntimeManager, and AXRemoteElement):

- **Private APIs are designed for external clients** (VoiceOver, assistive technologies)
- **In-process APIs return nil or limited data** (e.g., `currentApplication` returns nil)
- **Public UIAccessibility APIs already expose everything we need**

### Recommended Implementation

Add a single convenience method to AccessibilitySnapshot:

```swift
extension AccessibilityHierarchyParser {
    static func getRootViewFromSwiftUIApp() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                  .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootView = window.rootViewController?.view else {
            return nil
        }
        return rootView
    }
}
```

This enables AccessibilitySnapshot for SwiftUI lifecycle apps with ~10 lines of code.

---

## References

- AccessibilitySnapshot repo: https://github.com/cashapp/AccessibilitySnapshot
- Test app: `test-aoo/`
- Class introspection tool: `test-aoo/test-aoo/ClassIntrospector.swift`
- Research plan: `thoughts/shared/plans/2026-01-31-swiftui-accessibility-research.md`
