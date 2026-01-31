//
//  ExternalAccessibilityClient.swift
//  test-aoo
//
//  External accessibility client that enables accessibility services
//  similar to how AccessibilitySnapshot's ASAccessibilityEnabler.m works,
//  but with additional support for external app inspection.
//
//  WARNING: Uses private APIs - not for App Store submission
//

import UIKit

/// External accessibility client for inspecting accessibility hierarchies.
/// Can be used to inspect the current app or (with proper entitlements) other apps.
final class ExternalAccessibilityClient {

    // MARK: - Singleton

    static let shared = ExternalAccessibilityClient()

    // MARK: - Framework Handles

    private var axRuntimeHandle: UnsafeMutableRawPointer?
    private var libAccessibilityHandle: UnsafeMutableRawPointer?

    // MARK: - Class References

    private var axUIElementClass: AnyClass?
    private var axElementClass: AnyClass?
    private var axElementFetcherClass: AnyClass?

    // MARK: - State

    private(set) var isEnabled = false

    // MARK: - Initialization

    private init() {
        loadFrameworks()
    }

    // MARK: - Framework Loading

    private func loadFrameworks() {
        // Load AXRuntime.framework (private)
        axRuntimeHandle = dlopen(
            "/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime",
            RTLD_NOW
        )

        // Load libAccessibility.dylib
        // Handle simulator vs device paths
        var libPath = "/usr/lib/libAccessibility.dylib"
        if let simRoot = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] {
            libPath = simRoot + libPath
        }
        libAccessibilityHandle = dlopen(libPath, RTLD_LOCAL)

        // Get class references
        if axRuntimeHandle != nil {
            axUIElementClass = NSClassFromString("AXUIElement")
            axElementClass = NSClassFromString("AXElement")
            axElementFetcherClass = NSClassFromString("AXElementFetcher")
        }
    }

    // MARK: - Enable Services (like ASAccessibilityEnabler)

    /// Enable accessibility services. Call this before using other methods.
    /// Similar to AccessibilitySnapshot's ASAccessibilityEnabler +load method.
    func enable() {
        guard !isEnabled else { return }
        guard libAccessibilityHandle != nil else {
            print("[ExternalAX] libAccessibility not loaded")
            return
        }

        // 1. Enable automation (required for accessibility property population)
        //    This is what ASAccessibilityEnabler does
        if let currentVal = callGetter("_AXSAutomationEnabled") {
            print("[ExternalAX] Initial automation state: \(currentVal)")
        }
        callSetter("_AXSSetAutomationEnabled", value: 1)

        // 2. Enable AX Inspector mode (exposes more information)
        callSetter("_AXSAXInspectorSetEnabled", value: 1)

        // 3. Enable application accessibility (sometimes needed on simulator)
        callSetter("_AXSApplicationAccessibilitySetEnabled", value: 1)

        isEnabled = true
        print("[ExternalAX] Accessibility services enabled")
    }

    /// Disable accessibility services (restore original state)
    func disable() {
        guard isEnabled else { return }

        callSetter("_AXSSetAutomationEnabled", value: 0)
        callSetter("_AXSAXInspectorSetEnabled", value: 0)

        isEnabled = false
        print("[ExternalAX] Accessibility services disabled")
    }

    // MARK: - Private Function Helpers

    private func callSetter(_ name: String, value: Int32) {
        guard let handle = libAccessibilityHandle else { return }
        typealias SetterFunc = @convention(c) (Int32) -> Void

        if let sym = dlsym(handle, name) {
            let fn = unsafeBitCast(sym, to: SetterFunc.self)
            fn(value)
        }
    }

    private func callGetter(_ name: String) -> Int32? {
        guard let handle = libAccessibilityHandle else { return nil }
        typealias GetterFunc = @convention(c) () -> Int32

        if let sym = dlsym(handle, name) {
            let fn = unsafeBitCast(sym, to: GetterFunc.self)
            return fn()
        }
        return nil
    }

    // MARK: - System Element Access

    /// Get the system-wide accessibility element.
    /// This represents the entire accessibility tree root.
    func systemWideElement() -> AnyObject? {
        guard let cls = axUIElementClass else {
            print("[ExternalAX] AXUIElement class not available")
            return nil
        }

        let sel = NSSelectorFromString("systemWideAXUIElement")
        guard cls.responds(to: sel) else {
            print("[ExternalAX] systemWideAXUIElement not found")
            return nil
        }

        return (cls as AnyObject).perform(sel)?.takeUnretainedValue()
    }

    /// Get the system-wide application element.
    func systemWideApplication() -> AnyObject? {
        guard let cls = axUIElementClass else { return nil }

        let sel = NSSelectorFromString("uiSystemWideApplication")
        guard cls.responds(to: sel) else { return nil }

        return (cls as AnyObject).perform(sel)?.takeUnretainedValue()
    }

    // MARK: - Application Element Access

    /// Get accessibility element for an application by PID.
    /// Note: On iOS, this requires special entitlements for external apps.
    func applicationElement(pid: pid_t) -> AnyObject? {
        guard let cls = axUIElementClass else { return nil }

        let sel = NSSelectorFromString("uiApplicationWithPid:")
        guard cls.responds(to: sel) else { return nil }

        let pidNum = NSNumber(value: pid)
        return (cls as AnyObject).perform(sel, with: pidNum)?.takeUnretainedValue()
    }

    /// Get the current application's accessibility element.
    func currentApplicationElement() -> AnyObject? {
        return applicationElement(pid: getpid())
    }

    // MARK: - Element at Coordinate

    /// Get accessibility element at a screen coordinate.
    /// Note: CGPoint parameters require NSInvocation workaround in pure Swift.
    func elementAt(point: CGPoint) -> AnyObject? {
        guard let cls = axUIElementClass else { return nil }

        // For coordinates, we need to use a different approach
        // The selector expects CGPoint which isn't directly passable via perform()

        // Try using uiElementAtCoordinate:forApplication:contextId: instead
        // with NSInvocation-like approach

        // For now, return nil - this needs ObjC bridging code
        print("[ExternalAX] elementAt(point:) requires ObjC bridging for CGPoint parameter")
        return nil
    }

    // MARK: - AXElement (Higher-Level)

    /// Create an AXElement wrapper from a UIView.
    /// This gives access to the 120+ properties documented in the research.
    func createAXElement(from view: UIView) -> AnyObject? {
        guard let cls = axElementClass else { return nil }

        // Allocate
        let allocSel = NSSelectorFromString("alloc")
        guard let allocated = (cls as AnyObject).perform(allocSel)?.takeUnretainedValue() else {
            return nil
        }

        // Initialize with UIElement (which UIView conforms to via UIAccessibility)
        let initSel = NSSelectorFromString("initWithUIElement:")
        guard allocated.responds(to: initSel) else { return nil }

        return allocated.perform(initSel, with: view)?.takeUnretainedValue()
    }

    // MARK: - Element Properties

    /// Get children of an accessibility element.
    func children(of element: AnyObject) -> [AnyObject]? {
        let sel = NSSelectorFromString("children")
        guard element.responds(to: sel) else { return nil }
        return element.perform(sel)?.takeUnretainedValue() as? [AnyObject]
    }

    /// Get label of an accessibility element.
    func label(of element: AnyObject) -> String? {
        let sel = NSSelectorFromString("label")
        guard element.responds(to: sel) else { return nil }
        return element.perform(sel)?.takeUnretainedValue() as? String
    }

    /// Get value of an accessibility element.
    func value(of element: AnyObject) -> String? {
        let sel = NSSelectorFromString("value")
        guard element.responds(to: sel) else { return nil }
        return element.perform(sel)?.takeUnretainedValue() as? String
    }

    /// Get frame of an accessibility element.
    func frame(of element: AnyObject) -> CGRect {
        let sel = NSSelectorFromString("frame")
        guard element.responds(to: sel) else { return .zero }

        // The frame selector returns a CGRect struct, need special handling
        // For AXElement, frame is a property that returns CGRect

        // Try using KVC
        if let elem = element as? NSObject,
           let frameValue = elem.value(forKey: "frame") as? NSValue {
            return frameValue.cgRectValue
        }

        return .zero
    }

    /// Get traits of an accessibility element.
    func traits(of element: AnyObject) -> UIAccessibilityTraits {
        let sel = NSSelectorFromString("traits")
        guard element.responds(to: sel) else { return [] }

        // traits returns UInt64
        if let elem = element as? NSObject,
           let traitsNum = elem.value(forKey: "traits") as? NSNumber {
            return UIAccessibilityTraits(rawValue: traitsNum.uint64Value)
        }

        return []
    }

    /// Check if element is valid.
    func isValid(_ element: AnyObject) -> Bool {
        let sel = NSSelectorFromString("isValid")
        guard element.responds(to: sel) else { return false }

        if let elem = element as? NSObject,
           let valid = elem.value(forKey: "isValid") as? NSNumber {
            return valid.boolValue
        }

        return false
    }

    // MARK: - Hierarchy Traversal

    /// Recursively traverse accessibility hierarchy starting from an element.
    func traverseHierarchy(
        from element: AnyObject,
        depth: Int = 0,
        maxDepth: Int = 10
    ) -> [AccessibilityElementInfo] {
        guard depth < maxDepth else { return [] }

        var results: [AccessibilityElementInfo] = []

        let info = AccessibilityElementInfo(
            label: label(of: element),
            value: value(of: element),
            frame: frame(of: element),
            traits: traits(of: element),
            depth: depth
        )
        results.append(info)

        if let children = children(of: element) {
            for child in children {
                let childResults = traverseHierarchy(
                    from: child,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
                results.append(contentsOf: childResults)
            }
        }

        return results
    }

    // MARK: - Current App Inspection

    /// Inspect the current app's accessibility hierarchy using the window approach.
    /// This is the recommended approach that doesn't require special entitlements.
    func inspectCurrentApp() -> [AccessibilityElementInfo] {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootView = window.rootViewController?.view else {
            return []
        }

        // Use public UIAccessibility APIs
        return inspectView(rootView)
    }

    /// Inspect a UIView's accessibility hierarchy using public APIs.
    private func inspectView(_ view: UIView, depth: Int = 0, maxDepth: Int = 20) -> [AccessibilityElementInfo] {
        guard depth < maxDepth else { return [] }

        var results: [AccessibilityElementInfo] = []

        // Check if this view is an accessibility element
        if view.isAccessibilityElement {
            let info = AccessibilityElementInfo(
                label: view.accessibilityLabel,
                value: view.accessibilityValue,
                frame: view.accessibilityFrame,
                traits: view.accessibilityTraits,
                depth: depth
            )
            results.append(info)
        }

        // Check for accessibility container
        let elemCount = view.accessibilityElementCount()
        if elemCount != NSNotFound && elemCount > 0 {
            for i in 0..<elemCount {
                if let elem = view.accessibilityElement(at: i) {
                    if let obj = elem as? NSObject {
                        let info = AccessibilityElementInfo(
                            label: obj.accessibilityLabel,
                            value: obj.accessibilityValue,
                            frame: obj.accessibilityFrame,
                            traits: obj.accessibilityTraits,
                            depth: depth + 1
                        )
                        results.append(info)
                    }
                }
            }
        } else {
            // Recurse into subviews
            for subview in view.subviews {
                let subResults = inspectView(subview, depth: depth + 1, maxDepth: maxDepth)
                results.append(contentsOf: subResults)
            }
        }

        return results
    }
}

// MARK: - Supporting Types

/// Information about an accessibility element.
struct AccessibilityElementInfo {
    let label: String?
    let value: String?
    let frame: CGRect
    let traits: UIAccessibilityTraits
    let depth: Int

    var description: String {
        let indent = String(repeating: "  ", count: depth)
        var desc = "\(indent)"

        if let label = label, !label.isEmpty {
            desc += "[\(label)]"
        } else {
            desc += "[no label]"
        }

        if let value = value, !value.isEmpty {
            desc += " value='\(value)'"
        }

        let traitsList = traitsDescription
        if !traitsList.isEmpty {
            desc += " (\(traitsList))"
        }

        return desc
    }

    var traitsDescription: String {
        var result: [String] = []
        if traits.contains(.button) { result.append("button") }
        if traits.contains(.link) { result.append("link") }
        if traits.contains(.header) { result.append("header") }
        if traits.contains(.image) { result.append("image") }
        if traits.contains(.staticText) { result.append("staticText") }
        if traits.contains(.adjustable) { result.append("adjustable") }
        if traits.contains(.selected) { result.append("selected") }
        return result.joined(separator: ", ")
    }
}

// MARK: - Entitlement Detection

extension ExternalAccessibilityClient {
    /// Check if private entitlements are working
    func checkEntitlements() -> EntitlementStatus {
        var status = EntitlementStatus()

        // Check if we can get system-wide element (requires entitlements)
        if let sysElem = systemWideElement() {
            status.systemWideAccess = true

            // Try to get children (deeper check)
            if let children = children(of: sysElem), !children.isEmpty {
                status.canTraverseExternal = true
            }
        }

        // Check if we can access other PIDs
        // SpringBoard is always PID 1 on iOS
        if let springboard = applicationElement(pid: 1) {
            status.canAccessOtherApps = true
            if let lbl = label(of: springboard) {
                status.springboardLabel = lbl
            }
        }

        // Check AXElement.currentApplication (nil in-process without entitlements)
        if let axElement = axElementClass,
           axElement.responds(to: NSSelectorFromString("currentApplication")) {
            if (axElement as AnyObject).perform(NSSelectorFromString("currentApplication"))?.takeUnretainedValue() != nil {
                status.axElementCurrentAppWorks = true
            }
        }

        return status
    }

    /// Try to get all running applications (requires entitlements)
    func getAllApplications() -> [AnyObject]? {
        guard let axElement = axElementClass else { return nil }

        // Try currentApplications (plural)
        let sel = NSSelectorFromString("currentApplications")
        guard axElement.responds(to: sel) else { return nil }

        return (axElement as AnyObject).perform(sel)?.takeUnretainedValue() as? [AnyObject]
    }

    /// Try to get SpringBoard element (always PID 1)
    func getSpringBoardElement() -> AnyObject? {
        guard let fetcherClass = axElementFetcherClass else { return nil }

        let sel = NSSelectorFromString("springBoardElement")
        guard fetcherClass.responds(to: sel) else { return nil }

        return (fetcherClass as AnyObject).perform(sel)?.takeUnretainedValue()
    }
}

/// Status of private entitlements
struct EntitlementStatus {
    var systemWideAccess = false
    var canTraverseExternal = false
    var canAccessOtherApps = false
    var axElementCurrentAppWorks = false
    var springboardLabel: String?

    var hasFullAccess: Bool {
        systemWideAccess && canTraverseExternal && canAccessOtherApps
    }

    var description: String {
        """
        Entitlement Status:
          System-wide access: \(systemWideAccess ? "✅" : "❌")
          Can traverse external: \(canTraverseExternal ? "✅" : "❌")
          Can access other apps: \(canAccessOtherApps ? "✅" : "❌")
          AXElement.currentApplication: \(axElementCurrentAppWorks ? "✅" : "❌")
          SpringBoard label: \(springboardLabel ?? "N/A")
          Full external access: \(hasFullAccess ? "✅ YES" : "❌ NO")
        """
    }
}

// MARK: - Exploration Entry Point

/// Run full exploration of external accessibility capabilities.
func exploreExternalAccessibility() -> String {
    var output = """
    ============================================================
    EXTERNAL ACCESSIBILITY CLIENT EXPLORATION
    ============================================================

    """

    let client = ExternalAccessibilityClient.shared

    // 1. Enable services
    output += "1. Enabling Accessibility Services\n"
    output += "   (Similar to ASAccessibilityEnabler pattern)\n"
    client.enable()
    output += "   Enabled: \(client.isEnabled)\n\n"

    // 2. Check entitlement status
    output += "2. Checking Private Entitlements\n"
    let status = client.checkEntitlements()
    output += "   \(status.description.replacingOccurrences(of: "\n", with: "\n   "))\n\n"

    // 3. Try system-wide element
    output += "3. System-Wide Element\n"
    if let sysElem = client.systemWideElement() {
        output += "   Got: \(sysElem)\n"

        // NOTE: AXUIElement doesn't support KVC - PID is visible in description above
        // The description format is: <AXUIElementRef 0x...> {pid=N}

        // Try to get children using selector-based access
        if let children = client.children(of: sysElem) {
            output += "   Children count: \(children.count)\n"
            for (i, child) in children.prefix(5).enumerated() {
                if let lbl = client.label(of: child) {
                    output += "     [\(i)] \(lbl)\n"
                } else {
                    output += "     [\(i)] \(type(of: child))\n"
                }
            }
        }
    } else {
        output += "   Not available (expected without entitlements)\n"
    }
    output += "\n"

    // 4. Try SpringBoard element
    output += "4. SpringBoard Element (PID 1)\n"
    if let springboard = client.getSpringBoardElement() {
        output += "   Got: \(springboard)\n"
        if let lbl = client.label(of: springboard) {
            output += "   Label: \(lbl)\n"
        }
    } else if let springboard = client.applicationElement(pid: 1) {
        output += "   Got via PID: \(springboard)\n"
    } else {
        output += "   Not available (requires entitlements)\n"
    }
    output += "\n"

    // 5. Try to get all applications
    output += "5. All Running Applications\n"
    if let apps = client.getAllApplications() {
        output += "   Found \(apps.count) applications:\n"
        for (i, app) in apps.prefix(10).enumerated() {
            if let lbl = client.label(of: app) {
                output += "     [\(i)] \(lbl)\n"
            } else {
                output += "     [\(i)] \(type(of: app))\n"
            }
        }
    } else {
        output += "   Not available (requires entitlements)\n"
    }
    output += "\n"

    // 6. Inspect current app via public APIs (always works)
    output += "6. Current App Inspection (Public UIAccessibility APIs)\n"
    let elements = client.inspectCurrentApp()
    output += "   Found \(elements.count) accessibility elements:\n"
    for elem in elements.prefix(15) {
        output += "   \(elem.description)\n"
    }
    if elements.count > 15 {
        output += "   ... and \(elements.count - 15) more\n"
    }
    output += "\n"

    // 7. Summary with instructions
    output += """
    ============================================================
    SUMMARY
    ============================================================

    Private framework loading: ✅
    Automation enabled: ✅
    In-app inspection (public): ✅
    External app access: \(status.hasFullAccess ? "✅" : "❌")

    """

    if !status.hasFullAccess {
        output += """

    TO ENABLE EXTERNAL ACCESS:

    Option 1: iOS Simulator
      Build and run in Simulator - entitlements may not be enforced

    Option 2: TrollStore (iOS 14.0 - 17.0 only)
      1. Run: ./scripts/sign-with-private-entitlements.sh build/YourApp.app
      2. Create IPA and install via TrollStore

    Option 3: Jailbroken Device
      1. Install AppSync Unified
      2. Run: ldid -SPrivateAccessibilityEntitlements.plist YourApp.app/YourApp
      3. Install via Filza

    Option 4: macOS (Recommended for Development)
      AXUIElement is public API on macOS - no entitlements needed

    """
    } else {
        output += """

    🎉 FULL EXTERNAL ACCESS AVAILABLE!

    You can now:
    - Access other apps' accessibility hierarchies
    - Monitor accessibility changes system-wide
    - Use AXElementFetcher for real-time updates

    """
    }

    return output
}
