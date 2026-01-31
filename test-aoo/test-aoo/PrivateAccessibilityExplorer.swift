//
//  PrivateAccessibilityExplorer.swift
//  test-aoo
//
//  Experimental code for exploring iOS accessibility private APIs
//  WARNING: Uses private APIs - not for App Store submission
//

import UIKit

/// Explores iOS private accessibility APIs for research purposes
final class PrivateAccessibilityExplorer {

    // MARK: - Singleton

    static let shared = PrivateAccessibilityExplorer()

    // MARK: - Private Properties

    private var axRuntimeHandle: UnsafeMutableRawPointer?
    private var axUIElementClass: AnyClass?
    private var axElementClass: AnyClass?
    private var axElementFetcherClass: AnyClass?
    private var axSimpleRuntimeManagerClass: AnyClass?

    // MARK: - Initialization

    private init() {
        loadPrivateFrameworks()
    }

    // MARK: - Framework Loading

    private func loadPrivateFrameworks() {
        // Load AXRuntime.framework
        axRuntimeHandle = dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW)

        if axRuntimeHandle != nil {
            print("[PrivateAX] Successfully loaded AXRuntime.framework")

            // Get classes
            axUIElementClass = NSClassFromString("AXUIElement")
            axElementClass = NSClassFromString("AXElement")
            axElementFetcherClass = NSClassFromString("AXElementFetcher")
            axSimpleRuntimeManagerClass = NSClassFromString("AXSimpleRuntimeManager")

            print("[PrivateAX] AXUIElement: \(axUIElementClass != nil)")
            print("[PrivateAX] AXElement: \(axElementClass != nil)")
            print("[PrivateAX] AXElementFetcher: \(axElementFetcherClass != nil)")
            print("[PrivateAX] AXSimpleRuntimeManager: \(axSimpleRuntimeManagerClass != nil)")
        } else {
            print("[PrivateAX] Failed to load AXRuntime.framework")
            if let error = dlerror() {
                print("[PrivateAX] Error: \(String(cString: error))")
            }
        }
    }

    // MARK: - AX Inspector Mode

    /// Enable AX Inspector mode (might expose additional accessibility info)
    func enableAXInspector() {
        // Try to enable AX Inspector via libAccessibility
        typealias SetAXInspectorFunc = @convention(c) (Int32) -> Void
        typealias GetAXInspectorFunc = @convention(c) () -> Int32

        if let libHandle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW) {
            if let setFunc = dlsym(libHandle, "_AXSAXInspectorSetEnabled") {
                let setter = unsafeBitCast(setFunc, to: SetAXInspectorFunc.self)
                setter(1)
                print("[PrivateAX] AX Inspector enabled")
            }

            if let getFunc = dlsym(libHandle, "_AXSAXInspectorEnabled") {
                let getter = unsafeBitCast(getFunc, to: GetAXInspectorFunc.self)
                print("[PrivateAX] AX Inspector status: \(getter())")
            }
        }
    }

    // MARK: - System Wide Element Access

    /// Get the system-wide accessibility element
    func getSystemWideElement() -> AnyObject? {
        guard let axUIElementClass = axUIElementClass else {
            print("[PrivateAX] AXUIElement class not available")
            return nil
        }

        let selector = NSSelectorFromString("systemWideAXUIElement")
        guard axUIElementClass.responds(to: selector) else {
            print("[PrivateAX] systemWideAXUIElement selector not found")
            return nil
        }

        let result = (axUIElementClass as AnyObject).perform(selector)?.takeUnretainedValue()
        print("[PrivateAX] System-wide element: \(String(describing: result))")
        return result
    }

    // MARK: - Element at Coordinate

    /// Get accessibility element at a specific screen coordinate
    func getElementAt(point: CGPoint) -> AnyObject? {
        guard let axUIElementClass = axUIElementClass else {
            print("[PrivateAX] AXUIElement class not available")
            return nil
        }

        // This is tricky because the method takes a CGPoint, not an object
        // We need to use NSInvocation or similar approach
        let selector = NSSelectorFromString("uiElementAtCoordinate:")

        guard axUIElementClass.responds(to: selector) else {
            print("[PrivateAX] uiElementAtCoordinate: selector not found")
            return nil
        }

        // For complex argument types, we need NSInvocation
        // Since Swift doesn't have NSInvocation, we'll try a different approach
        print("[PrivateAX] Note: uiElementAtCoordinate: requires NSInvocation for CGPoint arg")
        return nil
    }

    // MARK: - Runtime Manager

    /// Get the shared runtime manager
    func getSharedManager() -> AnyObject? {
        guard let managerClass = axSimpleRuntimeManagerClass else {
            print("[PrivateAX] AXSimpleRuntimeManager class not available")
            return nil
        }

        let selector = NSSelectorFromString("sharedManager")
        guard managerClass.responds(to: selector) else {
            print("[PrivateAX] sharedManager selector not found")
            return nil
        }

        let result = (managerClass as AnyObject).perform(selector)?.takeUnretainedValue()
        print("[PrivateAX] Shared manager: \(String(describing: result))")
        return result
    }

    // MARK: - AXElement Exploration

    /// Create an AXElement from a UIView
    func createAXElement(from view: UIView) -> AnyObject? {
        guard let axElementClass = axElementClass else {
            print("[PrivateAX] AXElement class not available")
            return nil
        }

        // Try to initialize with UIElement
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString("initWithUIElement:")

        guard axElementClass.responds(to: allocSelector) else {
            print("[PrivateAX] alloc selector not found on AXElement")
            return nil
        }

        guard let allocated = (axElementClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() else {
            print("[PrivateAX] Failed to allocate AXElement")
            return nil
        }

        guard allocated.responds(to: initSelector) else {
            print("[PrivateAX] initWithUIElement: selector not found")
            return nil
        }

        let result = allocated.perform(initSelector, with: view)?.takeUnretainedValue()
        print("[PrivateAX] Created AXElement: \(String(describing: result))")
        return result
    }

    /// Get current application from an AXElement
    func getCurrentApplication(from element: AnyObject) -> AnyObject? {
        let selector = NSSelectorFromString("currentApplication")
        guard element.responds(to: selector) else {
            print("[PrivateAX] currentApplication selector not found")
            return nil
        }

        let result = element.perform(selector)?.takeUnretainedValue()
        print("[PrivateAX] Current application: \(String(describing: result))")
        return result
    }

    // MARK: - Element Fetcher

    /// Create an AXElementFetcher to traverse the accessibility tree
    func createElementFetcher() -> AnyObject? {
        guard let fetcherClass = axElementFetcherClass else {
            print("[PrivateAX] AXElementFetcher class not available")
            return nil
        }

        // The init method has many parameters, try basic alloc/init first
        let allocSelector = NSSelectorFromString("alloc")

        guard fetcherClass.responds(to: allocSelector) else {
            print("[PrivateAX] alloc selector not found on AXElementFetcher")
            return nil
        }

        guard let allocated = (fetcherClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() else {
            print("[PrivateAX] Failed to allocate AXElementFetcher")
            return nil
        }

        // Try simpler init if available
        let initSelector = NSSelectorFromString("init")
        if allocated.responds(to: initSelector) {
            let result = allocated.perform(initSelector)?.takeUnretainedValue()
            print("[PrivateAX] Created AXElementFetcher: \(String(describing: result))")
            return result
        }

        print("[PrivateAX] AXElementFetcher requires complex initialization")
        return nil
    }

    /// Get the root group from an element fetcher
    func getRootGroup(from fetcher: AnyObject) -> AnyObject? {
        let selector = NSSelectorFromString("rootGroup")
        guard fetcher.responds(to: selector) else {
            print("[PrivateAX] rootGroup selector not found")
            return nil
        }

        let result = fetcher.perform(selector)?.takeUnretainedValue()
        print("[PrivateAX] Root group: \(String(describing: result))")
        return result
    }

    /// Get available elements from a fetcher
    func getAvailableElements(from fetcher: AnyObject) -> AnyObject? {
        let selector = NSSelectorFromString("availableElements")
        guard fetcher.responds(to: selector) else {
            print("[PrivateAX] availableElements selector not found")
            return nil
        }

        let result = fetcher.perform(selector)?.takeUnretainedValue()
        print("[PrivateAX] Available elements: \(String(describing: result))")
        return result
    }

    // MARK: - Full Exploration

    /// Run a comprehensive exploration of available private APIs
    func runFullExploration() -> String {
        var output = "=== Private Accessibility API Exploration ===\n\n"

        // 1. Check framework loading
        output += "1. Framework Loading:\n"
        output += "   AXRuntime loaded: \(axRuntimeHandle != nil)\n"
        output += "   AXUIElement: \(axUIElementClass != nil)\n"
        output += "   AXElement: \(axElementClass != nil)\n"
        output += "   AXElementFetcher: \(axElementFetcherClass != nil)\n"
        output += "   AXSimpleRuntimeManager: \(axSimpleRuntimeManagerClass != nil)\n\n"

        // 2. Enable AX Inspector
        output += "2. AX Inspector:\n"
        enableAXInspector()
        output += "   Enabled AX Inspector mode\n\n"

        // 3. Try system-wide element
        output += "3. System-Wide Element:\n"
        if let sysElement = getSystemWideElement() {
            output += "   Got: \(sysElement)\n"
        } else {
            output += "   Could not get system-wide element\n"
        }
        output += "\n"

        // 4. Try to get current application element
        output += "4. Current Application:\n"
        output += exploreCurrentApplication()
        output += "\n"

        // 5. Try AXElement with UIView
        output += "5. AXElement from Root View:\n"
        output += exploreAXElementFromView()
        output += "\n"

        // 6. Explore children/attributes of system element
        output += "6. System Element Children:\n"
        output += exploreSystemElementChildren()
        output += "\n"

        // 7. Explore AXElementFetcher
        output += "7. AXElementFetcher Exploration:\n"
        output += exploreElementFetcher()
        output += "\n"

        // 8. Explore focused element
        output += "8. Focused/First Responder Element:\n"
        output += exploreFocusedElement()
        output += "\n"

        return output
    }

    // MARK: - Deep Exploration

    private func exploreCurrentApplication() -> String {
        var output = ""

        guard let axElementClass = axElementClass else {
            return "   AXElement class not available\n"
        }

        // Allocate and try to get current application
        let allocSel = NSSelectorFromString("alloc")
        guard let allocated = (axElementClass as AnyObject).perform(allocSel)?.takeUnretainedValue() else {
            return "   Could not allocate AXElement\n"
        }

        // Try basic init first
        let initSel = NSSelectorFromString("init")
        if allocated.responds(to: initSel) {
            if let initialized = allocated.perform(initSel)?.takeUnretainedValue() {
                output += "   Created AXElement instance\n"

                // Try currentApplication
                let currentAppSel = NSSelectorFromString("currentApplication")
                if initialized.responds(to: currentAppSel) {
                    if let app = initialized.perform(currentAppSel)?.takeUnretainedValue() {
                        output += "   currentApplication: \(app)\n"
                    } else {
                        output += "   currentApplication: nil\n"
                    }
                }

                // Try currentApplications
                let currentAppsSel = NSSelectorFromString("currentApplications")
                if initialized.responds(to: currentAppsSel) {
                    if let apps = initialized.perform(currentAppsSel)?.takeUnretainedValue() {
                        output += "   currentApplications: \(apps)\n"
                    } else {
                        output += "   currentApplications: nil\n"
                    }
                }
            }
        }

        return output
    }

    private func exploreAXElementFromView() -> String {
        var output = ""

        // Get the root view from the app
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootView = window.rootViewController?.view else {
            return "   Could not get root view\n"
        }

        output += "   Root view type: \(type(of: rootView))\n"
        output += "   Window frame: \(window.frame)\n"

        // Approach 1: Try to get AXUIElement for the app via coordinate
        output += "\n   --- Approach 1: Element at coordinate ---\n"
        let centerPoint = CGPoint(x: window.frame.midX, y: window.frame.midY)
        output += "   Center point: \(centerPoint)\n"

        if let axUIElementClass = axUIElementClass {
            // Try uiApplicationAtCoordinate:
            let appAtCoordSel = NSSelectorFromString("uiApplicationAtCoordinate:")
            if axUIElementClass.responds(to: appAtCoordSel) {
                output += "   uiApplicationAtCoordinate: available (needs NSInvocation for CGPoint)\n"
            }

            // Try uiSystemWideApplication
            let sysAppSel = NSSelectorFromString("uiSystemWideApplication")
            if axUIElementClass.responds(to: sysAppSel) {
                if let sysApp = (axUIElementClass as AnyObject).perform(sysAppSel)?.takeUnretainedValue() {
                    output += "   uiSystemWideApplication: \(sysApp)\n"
                } else {
                    output += "   uiSystemWideApplication: nil\n"
                }
            } else {
                output += "   uiSystemWideApplication: not available\n"
            }
        }

        // Approach 2: Explore UIView's accessibility properties directly
        output += "\n   --- Approach 2: UIView accessibility introspection ---\n"
        output += "   isAccessibilityElement: \(rootView.isAccessibilityElement)\n"
        output += "   accessibilityElementCount: \(rootView.accessibilityElementCount())\n"

        // Get accessibility elements from the view
        let elemCount = rootView.accessibilityElementCount()
        if elemCount != NSNotFound && elemCount > 0 {
            output += "   Found \(elemCount) accessibility elements in root view:\n"
            for i in 0..<min(elemCount, 10) {
                if let elem = rootView.accessibilityElement(at: i) {
                    output += "     [\(i)]: \(type(of: elem))\n"
                    if let accessible = elem as? NSObject {
                        if let label = accessible.accessibilityLabel {
                            output += "         label: \(label)\n"
                        }
                    }
                }
            }
        }

        // Approach 3: Check for _accessibilityUserTestingChildren (private)
        output += "\n   --- Approach 3: Private UIView methods ---\n"
        let privateSelectors = [
            "_accessibilityUserTestingChildren",
            "_accessibilityHitTest:",
            "_accessibilityRetrieveValue:",
            "accessibilityContainer",
            "_accessibilityAutomationType"
        ]

        for selName in privateSelectors {
            let sel = NSSelectorFromString(selName)
            if rootView.responds(to: sel) {
                if !selName.contains(":") {
                    // No args, can try to call
                    if let result = rootView.perform(sel)?.takeUnretainedValue() {
                        output += "   \(selName): \(result)\n"
                    } else {
                        output += "   \(selName): nil/void\n"
                    }
                } else {
                    output += "   \(selName): available (needs args)\n"
                }
            } else {
                output += "   \(selName): not available\n"
            }
        }

        return output
    }

    private func exploreSystemElementChildren() -> String {
        var output = ""

        guard let sysElement = getSystemWideElement() else {
            return "   No system element\n"
        }

        // Check what methods are available on the system element
        let selectors = [
            "children",
            "parent",
            "role",
            "title",
            "value",
            "pid",
            "isValid"
        ]

        for sel in selectors {
            let selector = NSSelectorFromString(sel)
            if sysElement.responds(to: selector) {
                // For simple selectors (no args), try to call
                if !sel.contains(":") {
                    if let result = sysElement.perform(selector)?.takeUnretainedValue() {
                        output += "   \(sel): \(result)\n"
                    } else {
                        output += "   \(sel): nil/void\n"
                    }
                } else {
                    output += "   \(sel): available (needs args)\n"
                }
            } else {
                output += "   \(sel): not available\n"
            }
        }

        // Try arrayWithAXAttribute for children (attribute ID for children is usually 4 or similar)
        let arraySel = NSSelectorFromString("arrayWithAXAttribute:")
        if sysElement.responds(to: arraySel) {
            output += "   arrayWithAXAttribute: available\n"
        }

        return output
    }

    private func exploreElementFetcher() -> String {
        var output = ""

        guard let fetcherClass = axElementFetcherClass else {
            return "   AXElementFetcher class not available\n"
        }

        // List available class methods
        output += "   Available class methods:\n"
        let classSelectors = [
            "sharedElementFetcher",
            "defaultFetcher",
            "currentFetcher"
        ]

        for selName in classSelectors {
            let sel = NSSelectorFromString(selName)
            if fetcherClass.responds(to: sel) {
                if let result = (fetcherClass as AnyObject).perform(sel)?.takeUnretainedValue() {
                    output += "   \(selName): \(result)\n"
                } else {
                    output += "   \(selName): nil\n"
                }
            } else {
                output += "   \(selName): not available\n"
            }
        }

        // List instance methods that would be available after init
        output += "\n   Instance methods to try (after initialization):\n"
        let instanceMethods = [
            "rootGroup",
            "availableElements",
            "currentApps",
            "nativeFocusElement",
            "keyboardGroup"
        ]
        for method in instanceMethods {
            output += "   - \(method)\n"
        }

        // Note about complex initialization
        output += "\n   Note: AXElementFetcher requires complex init with delegate/events\n"

        return output
    }

    private func exploreFocusedElement() -> String {
        var output = ""

        // Try UIAccessibility focused element
        let focusedElement = UIAccessibility.focusedElement(using: .notificationVoiceOver)
        output += "   VoiceOver focused: \(String(describing: focusedElement))\n"

        // Try getting first responder from window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return output + "   Could not access window\n"
        }

        // Get first responder via private method
        let firstResponderSel = NSSelectorFromString("firstResponder")
        if window.responds(to: firstResponderSel) {
            if let firstResponder = window.perform(firstResponderSel)?.takeUnretainedValue() {
                output += "   Window first responder: \(firstResponder)\n"
            } else {
                output += "   Window first responder: nil\n"
            }
        }

        // Check for accessibilityFocusedUIElement (macOS-style but might exist)
        let focusedUIElemSel = NSSelectorFromString("accessibilityFocusedUIElement")
        if window.responds(to: focusedUIElemSel) {
            if let focused = window.perform(focusedUIElemSel)?.takeUnretainedValue() {
                output += "   accessibilityFocusedUIElement: \(focused)\n"
            } else {
                output += "   accessibilityFocusedUIElement: nil\n"
            }
        } else {
            output += "   accessibilityFocusedUIElement: not available\n"
        }

        return output
    }
}
