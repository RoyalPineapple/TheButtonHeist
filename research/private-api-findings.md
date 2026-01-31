# iOS Accessibility Private API Findings

**Target:** iOS 18+

## iOS 18 Context

iOS 18 added new accessibility modifier parameters (`isEnabled`), drag/drop accessibility, and App Intent integration, but did **not** add any public API for programmatic accessibility tree introspection. The underlying architecture (`AXRuntime`, `UIAccessibility`) remains the same.

**Interesting lead:** `XCUIApplication.performAccessibilityAudit()` - suggests Apple has internal tree traversal code for auditing. Worth investigating how this accesses the tree.

---

## libAccessibility.dylib

### Currently Used by AccessibilitySnapshot
```c
// Enables accessibility without VoiceOver
int _AXSAutomationEnabled(void);
void _AXSSetAutomationEnabled(int enabled);
```

### Potentially Useful Functions

```c
// AX Inspector Mode - might expose more accessibility info
int _AXSAXInspectorEnabled(void);
void _AXSAXInspectorSetEnabled(int enabled);

// Audit mode
int _AXSAuditInspectionModeEnabled(void);
void _AXSSetAuditInspectionModeEnabled(int enabled);

// Isolated tree mode - might affect accessibility tree structure
int _AXSIsolatedTreeMode(void);
void _AXSSetIsolatedTreeMode(int enabled);

// Application accessibility
int _AXSApplicationAccessibilityEnabled(void);
void _AXSApplicationAccessibilitySetEnabled(int enabled);
```

## AXRuntime.framework Classes

### AXUIElement (Primary Interface)

```objc
@interface AXUIElement : NSObject

// Class Methods - Element Creation
+ (id)systemWideAXUIElement;
+ (id)uiSystemWideApplication;
+ (id)uiElementAtCoordinate:(CGPoint)point;
+ (id)uiElementAtCoordinate:(CGPoint)point forApplication:(struct __AXUIElement *)app contextId:(unsigned int)contextId;
+ (id)uiElementAtCoordinate:(CGPoint)point startWithElement:(id)element;
+ (id)uiApplicationAtCoordinate:(CGPoint)point;
+ (id)uiApplicationForContext:(id)context;
+ (id)uiElementWithAXElement:(struct __AXUIElement *)element;
+ (id)uiElementWithAXElement:(struct __AXUIElement *)element cache:(id)cache;

// Instance Methods - Element Properties
- (BOOL)isValid;
- (BOOL)isValidForApplication:(id)app;
- (int)pid;
- (struct __AXUIElement *)axElement;
- (id)cachedAttributes;

// Attribute Access
- (id)arrayWithAXAttribute:(long long)attr;
- (id)stringWithAXAttribute:(long long)attr;
- (BOOL)boolWithAXAttribute:(long long)attr;
- (id)numberWithAXAttribute:(long long)attr;
- (CGPoint)pointWithAXAttribute:(long long)attr;
- (struct CGPath *)pathWithAXAttribute:(long long)attr;
- (CGRect)rectWithAXAttribute:(long long)attr;
- (NSRange)rangeWithAXAttribute:(long long)attr;
- (id)objectWithAXAttribute:(long long)attr;
- (id)objectWithAXAttribute:(long long)attr parameter:(void *)param;

// Actions
- (BOOL)performAXAction:(int)action;
- (BOOL)performAXAction:(int)action withValue:(id)value;
- (BOOL)canPerformAXAction:(int)action;

// Cache Management
- (void)enableCache:(BOOL)enable;
- (void)disableCache;
- (void)updateCache:(long long)attrs;
- (void)updateCacheWithAttributes:(id)attrs;

@end
```

### AXElement (Higher-Level Wrapper)

```objc
@interface AXElement : NSObject

// Initialization
- (id)initWithUIElement:(id)uiElement;
- (id)initWithAXUIElement:(struct __AXUIElement *)element;

// Properties
- (struct __AXUIElement *)elementRef;
- (BOOL)isSystemWideElement;

// Element Hierarchy
- (id)elementForAttribute:(long long)attr;
- (id)elementsForAttribute:(long long)attr;
- (id)elementForAttribute:(long long)attr parameter:(id)param;
- (id)elementsForAttribute:(long long)attr parameter:(id)param;

// Application Access
- (id)currentApplication;
- (id)currentApplications;
- (id)currentApplicationsIgnoringSiri;

// Serialization
- (id)serializeToData;

// Context
- (unsigned int)contextIdForPoint:(CGPoint)point;
- (unsigned int)displayIdForContextId:(unsigned int)contextId;

@end
```

### AXElementFetcher (Accessibility Tree Traversal)

```objc
@interface AXElementFetcher : NSObject

// Initialization
- (id)initWithDelegate:(id)delegate
           fetchEvents:(id)events
 enableEventManagement:(BOOL)eventMgmt
        enableGrouping:(BOOL)grouping
shouldIncludeNonScannerElements:(BOOL)includeNonScanner
          beginEnabled:(BOOL)enabled;

// Element Access
- (id)rootGroup;              // Root group of all elements
- (id)availableElements;       // All available accessibility elements
- (BOOL)willFetchElements;     // Check if ready to fetch

// Application Access
- (id)currentApps;
- (BOOL)_updateCurrentApps;

// Focus
- (id)nativeFocusElement;

// Keyboard Access
- (id)keyboardGroup;
- (id)firstKeyboardRow;
- (id)lastKeyboardRow;

// Observers
- (void)registerFetchObserver:(id)observer targetQueue:(id)queue;
- (void)unregisterFetchObserver:(id)observer;
- (void)unregisterAllFetchObservers;

@end
```

### AXSimpleRuntimeManager (Singleton Manager)

```objc
@interface AXSimpleRuntimeManager : NSObject

+ (id)sharedManager;

@property (nonatomic) id systemWideServer;
@property (nonatomic, copy) id applicationElementCallback;

@end
```

### AXRemoteElement (Cross-Process)

```objc
@interface AXRemoteElement : NSObject

+ (id)remoteElementForBlock:(id)block;
+ (id)remoteElementsForBlock:(id)block;
+ (id)remoteElementsForContextId:(unsigned int)contextId;
+ (id)registeredRemoteElements;
+ (void)registerRemoteElement:(id)element;

@end
```

## Potential Usage Patterns

### Pattern 1: Get Root Accessibility Element via AXUIElement

```objc
// Load AXRuntime
void *handle = dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW);

// Get class
Class AXUIElementClass = NSClassFromString(@"AXUIElement");

// Get system-wide element (might give access to all apps)
id systemWide = [AXUIElementClass performSelector:@selector(systemWideAXUIElement)];

// Or get element at specific coordinate (useful for targeting our own app)
CGPoint center = CGPointMake(screenWidth/2, screenHeight/2);
id elementAtPoint = [AXUIElementClass performSelector:@selector(uiElementAtCoordinate:) withObject:@(center)];
```

### Pattern 2: Use AXElementFetcher for Tree Traversal

```objc
Class AXElementFetcherClass = NSClassFromString(@"AXElementFetcher");
id fetcher = [[AXElementFetcherClass alloc] initWithDelegate:nil
                                                fetchEvents:nil
                                      enableEventManagement:NO
                                             enableGrouping:YES
                             shouldIncludeNonScannerElements:YES
                                               beginEnabled:YES];

id rootGroup = [fetcher performSelector:@selector(rootGroup)];
id elements = [fetcher performSelector:@selector(availableElements)];
```

### Pattern 3: Access Current Application

```objc
Class AXElementClass = NSClassFromString(@"AXElement");
id element = [[AXElementClass alloc] init];
id currentApp = [element performSelector:@selector(currentApplication)];
```

## Risks and Considerations

1. **Private API changes**: These APIs may change between iOS versions
2. **App Store rejection**: Not applicable for testing tools
3. **Runtime loading**: Need to dlopen the frameworks
4. **Method signatures**: May need to use NSInvocation for complex types
5. **Coordinate spaces**: Element coordinates are in screen space, need conversion

---

## Experimental Results (iOS 18.2 Simulator)

### Test Environment
- iOS Simulator: iPhone 17 Pro (iOS 18.2)
- Test app: Pure SwiftUI lifecycle (`@main struct App: App`)
- Test UI: Image, Text, 2 Buttons, ScrollView with Text

### Key Finding: Standard UIAccessibility APIs Work for SwiftUI

**The existing AccessibilityHierarchyParser approach works perfectly for SwiftUI lifecycle apps!**

```swift
// Access UIWindow from SwiftUI app
guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first else { return }

let rootView = window.rootViewController?.view  // This is _UIHostingView
// Root VC type: UIHostingController<ModifiedContent<AnyView, RootModifier>>
// Root View type: _UIHostingView<ModifiedContent<AnyView, RootModifier>>
```

The public UIAccessibility APIs work directly on `_UIHostingView`:
```swift
rootView.accessibilityElementCount()  // Returns 5
rootView.accessibilityElement(at: 0)  // Returns SwiftUI.AccessibilityNode
```

### Private API Results

#### AXRuntime Loading: ✅ Success
- All classes loaded successfully
- `AXUIElement`, `AXElement`, `AXElementFetcher`, `AXSimpleRuntimeManager` available

#### AX Inspector Mode: ✅ Works
```swift
// _AXSAXInspectorSetEnabled(1) enables inspector mode
// _AXSAXInspectorEnabled() returns 1 when enabled
```

#### System-Wide Element: ✅ Accessible
```
<AXUIElementRef> {pid=0} {uid=[ID:1 hash:0x0]}
```
- pid=0 indicates system-wide (not app-specific)
- Cannot traverse children directly from system-wide element

#### uiSystemWideApplication: ✅ Works
```swift
// Returns: <AXUIElement: 0x600000c8ed60>
```

#### currentApplication/currentApplications: ❌ Returns nil
- These methods return nil when called from within the app
- May only work from external accessibility clients (like VoiceOver)

#### Key Private UIView Method Discovered: `_accessibilityUserTestingChildren`

```swift
// Returns array of SwiftUI.AccessibilityNode objects
rootView.perform(NSSelectorFromString("_accessibilityUserTestingChildren"))

// Output:
[
  "<SwiftUI.AccessibilityNode: 0x11a5101f0>",  // Globe icon
  "<SwiftUI.AccessibilityNode: 0x11a508800>",  // "Greeting" text
  "<SwiftUI.AccessibilityNode: 0x11a508e20>",  // "Inspect with parser" button
  "<SwiftUI.AccessibilityNode: 0x11a5091a0>",  // "Explore private APIs" button
  "<SwiftUI.HostingScrollView: 0x10305cc00>"   // ScrollView
]
```

This is the same data that `accessibilityElement(at:)` returns, but as an array.

### Conclusion

**No additional private APIs are needed for SwiftUI accessibility tree access.**

The existing approach in AccessibilitySnapshot works:
1. Get UIWindow via `UIApplication.shared.connectedScenes`
2. Get root view via `window.rootViewController?.view`
3. Use `AccessibilityHierarchyParser.parseAccessibilityElements(in: rootView)`

The key insight is that SwiftUI's `_UIHostingView` properly implements the standard UIAccessibility protocols, exposing `SwiftUI.AccessibilityNode` objects that contain all the accessibility information.

### Recommended Solution for AccessibilitySnapshot

For SwiftUI lifecycle apps, add a convenience method:

```swift
extension AccessibilityHierarchyParser {
    /// Get root view from SwiftUI app for accessibility parsing
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

---

## Next Steps

1. ~~Create Swift wrapper for these private APIs~~ (Not needed - standard APIs work)
2. ~~Test in simulator to verify functionality~~ (Verified - works)
3. ~~Compare output with current AccessibilitySnapshot parser~~ (Same results)
4. ~~Determine if this provides better access to SwiftUI hierarchy~~ (Standard APIs sufficient)

### Remaining Tasks
1. Document the UIWindow access pattern for SwiftUI lifecycle apps
2. Consider adding convenience methods to AccessibilitySnapshot
3. Test with more complex SwiftUI view hierarchies (nested views, lists, etc.)
4. Verify behavior with accessibility containers and custom accessibility elements
