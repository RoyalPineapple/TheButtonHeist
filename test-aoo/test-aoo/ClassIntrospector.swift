//
//  ClassIntrospector.swift
//  test-aoo
//
//  Runtime class introspection for reverse engineering SwiftUI internals
//

import UIKit
import ObjectiveC

/// Introspects Objective-C classes at runtime to discover methods and properties
final class ClassIntrospector {

    static let shared = ClassIntrospector()

    private init() {}

    // MARK: - Class Discovery

    /// Find all classes matching a pattern
    func findClasses(matching pattern: String) -> [String] {
        var results: [String] = []
        let count = objc_getClassList(nil, 0)
        guard count > 0 else { return results }

        let classes = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(count))
        defer { classes.deallocate() }

        let actualCount = objc_getClassList(AutoreleasingUnsafeMutablePointer(classes), count)

        for i in 0..<Int(actualCount) {
            if let cls = classes[i] {
                let name = String(cString: class_getName(cls))
                if name.lowercased().contains(pattern.lowercased()) {
                    results.append(name)
                }
            }
        }

        return results.sorted()
    }

    // MARK: - Method Introspection

    /// Get all instance methods for a class
    func getInstanceMethods(for className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return [] }
        return getInstanceMethods(for: cls)
    }

    func getInstanceMethods(for cls: AnyClass) -> [String] {
        var results: [String] = []
        var methodCount: UInt32 = 0

        if let methods = class_copyMethodList(cls, &methodCount) {
            for i in 0..<Int(methodCount) {
                let selector = method_getName(methods[i])
                let name = NSStringFromSelector(selector)
                results.append(name)
            }
            free(methods)
        }

        return results.sorted()
    }

    /// Get all class methods for a class
    func getClassMethods(for className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return [] }
        return getClassMethods(for: cls)
    }

    func getClassMethods(for cls: AnyClass) -> [String] {
        var results: [String] = []
        var methodCount: UInt32 = 0

        // Class methods are on the metaclass
        guard let metaCls = object_getClass(cls) else { return [] }

        if let methods = class_copyMethodList(metaCls, &methodCount) {
            for i in 0..<Int(methodCount) {
                let selector = method_getName(methods[i])
                let name = NSStringFromSelector(selector)
                results.append(name)
            }
            free(methods)
        }

        return results.sorted()
    }

    // MARK: - Property Introspection

    /// Get all properties for a class
    func getProperties(for className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return [] }
        return getProperties(for: cls)
    }

    func getProperties(for cls: AnyClass) -> [String] {
        var results: [String] = []
        var propertyCount: UInt32 = 0

        if let properties = class_copyPropertyList(cls, &propertyCount) {
            for i in 0..<Int(propertyCount) {
                let name = String(cString: property_getName(properties[i]))
                if let attributes = property_getAttributes(properties[i]) {
                    let attrs = String(cString: attributes)
                    results.append("\(name) (\(attrs))")
                } else {
                    results.append(name)
                }
            }
            free(properties)
        }

        return results.sorted()
    }

    // MARK: - Ivar Introspection

    /// Get all instance variables for a class
    func getIvars(for className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return [] }
        return getIvars(for: cls)
    }

    func getIvars(for cls: AnyClass) -> [String] {
        var results: [String] = []
        var ivarCount: UInt32 = 0

        if let ivars = class_copyIvarList(cls, &ivarCount) {
            for i in 0..<Int(ivarCount) {
                if let name = ivar_getName(ivars[i]) {
                    let nameStr = String(cString: name)
                    if let typeEncoding = ivar_getTypeEncoding(ivars[i]) {
                        let typeStr = String(cString: typeEncoding)
                        results.append("\(nameStr): \(decodeTypeEncoding(typeStr))")
                    } else {
                        results.append(nameStr)
                    }
                }
            }
            free(ivars)
        }

        return results.sorted()
    }

    // MARK: - Protocol Introspection

    /// Get all protocols adopted by a class
    func getProtocols(for className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return [] }
        return getProtocols(for: cls)
    }

    func getProtocols(for cls: AnyClass) -> [String] {
        var results: [String] = []
        var protocolCount: UInt32 = 0

        if let protocols = class_copyProtocolList(cls, &protocolCount) {
            for i in 0..<Int(protocolCount) {
                let name = String(cString: protocol_getName(protocols[i]))
                results.append(name)
            }
        }

        return results.sorted()
    }

    // MARK: - Superclass Chain

    /// Get the superclass chain for a class
    func getSuperclassChain(for className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return [] }
        return getSuperclassChain(for: cls)
    }

    func getSuperclassChain(for cls: AnyClass) -> [String] {
        var results: [String] = []
        var current: AnyClass? = cls

        while let c = current {
            results.append(String(cString: class_getName(c)))
            current = class_getSuperclass(c)
        }

        return results
    }

    // MARK: - Full Class Dump

    /// Generate a full class dump
    func dumpClass(_ className: String) -> String {
        guard let cls = NSClassFromString(className) else {
            return "Class '\(className)' not found"
        }

        var output = ""
        output += "=== Class: \(className) ===\n\n"

        // Superclass chain
        output += "Inheritance:\n"
        for (index, superclass) in getSuperclassChain(for: cls).enumerated() {
            output += "  \(String(repeating: "  ", count: index))\(superclass)\n"
        }
        output += "\n"

        // Protocols
        let protocols = getProtocols(for: cls)
        if !protocols.isEmpty {
            output += "Protocols (\(protocols.count)):\n"
            for proto in protocols {
                output += "  - \(proto)\n"
            }
            output += "\n"
        }

        // Properties
        let properties = getProperties(for: cls)
        if !properties.isEmpty {
            output += "Properties (\(properties.count)):\n"
            for prop in properties {
                output += "  - \(prop)\n"
            }
            output += "\n"
        }

        // Ivars
        let ivars = getIvars(for: cls)
        if !ivars.isEmpty {
            output += "Instance Variables (\(ivars.count)):\n"
            for ivar in ivars {
                output += "  - \(ivar)\n"
            }
            output += "\n"
        }

        // Instance methods
        let instanceMethods = getInstanceMethods(for: cls)
        if !instanceMethods.isEmpty {
            output += "Instance Methods (\(instanceMethods.count)):\n"
            for method in instanceMethods {
                output += "  - \(method)\n"
            }
            output += "\n"
        }

        // Class methods
        let classMethods = getClassMethods(for: cls)
        if !classMethods.isEmpty {
            output += "Class Methods (\(classMethods.count)):\n"
            for method in classMethods {
                output += "  + \(method)\n"
            }
            output += "\n"
        }

        return output
    }

    // MARK: - Helpers

    private func decodeTypeEncoding(_ encoding: String) -> String {
        // Basic type encoding decoder
        let first = encoding.first
        switch first {
        case "@": return "id/object"
        case "#": return "Class"
        case ":": return "SEL"
        case "c": return "char"
        case "i": return "int"
        case "s": return "short"
        case "l": return "long"
        case "q": return "long long"
        case "C": return "unsigned char"
        case "I": return "unsigned int"
        case "S": return "unsigned short"
        case "L": return "unsigned long"
        case "Q": return "unsigned long long"
        case "f": return "float"
        case "d": return "double"
        case "B": return "bool"
        case "v": return "void"
        case "*": return "char*"
        case "^": return "pointer"
        case "?": return "unknown/block"
        case "{": return "struct"
        default: return encoding
        }
    }
}

// MARK: - Exploration Functions

/// Explore SwiftUI accessibility internals
func exploreSwiftUIAccessibility() -> String {
    let introspector = ClassIntrospector.shared
    var output = ""

    output += "=" .padding(toLength: 60, withPad: "=", startingAt: 0) + "\n"
    output += "SWIFTUI ACCESSIBILITY INTERNALS\n"
    output += "=" .padding(toLength: 60, withPad: "=", startingAt: 0) + "\n\n"

    // Find SwiftUI accessibility-related classes
    output += ">>> Finding SwiftUI Accessibility Classes <<<\n\n"
    let accessibilityClasses = introspector.findClasses(matching: "AccessibilityNode")
    output += "Classes matching 'AccessibilityNode': \(accessibilityClasses.count)\n"
    for cls in accessibilityClasses.prefix(20) {
        output += "  - \(cls)\n"
    }
    output += "\n"

    // Find _UIHostingView classes
    let hostingClasses = introspector.findClasses(matching: "_UIHostingView")
    output += "Classes matching '_UIHostingView': \(hostingClasses.count)\n"
    for cls in hostingClasses.prefix(10) {
        output += "  - \(cls)\n"
    }
    output += "\n"

    // Dump AccessibilityNode if found
    if let nodeClass = accessibilityClasses.first(where: { $0.contains("SwiftUI") && $0.contains("AccessibilityNode") && !$0.contains("$") }) {
        output += "-" .padding(toLength: 60, withPad: "-", startingAt: 0) + "\n"
        output += introspector.dumpClass(nodeClass)
    }

    // Try to find the actual AccessibilityNode from a running view
    output += "-" .padding(toLength: 60, withPad: "-", startingAt: 0) + "\n"
    output += ">>> Inspecting Live AccessibilityNode <<<\n\n"

    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = windowScene.windows.first,
       let rootView = window.rootViewController?.view {

        let elemCount = rootView.accessibilityElementCount()
        if elemCount != NSNotFound && elemCount > 0 {
            if let firstElement = rootView.accessibilityElement(at: 0) {
                let elementType = type(of: firstElement)
                let className = String(describing: elementType)
                output += "First element type: \(className)\n"
                output += "Element class name: \(NSStringFromClass(type(of: firstElement as AnyObject)))\n\n"

                // Dump this class
                let fullClassName = NSStringFromClass(type(of: firstElement as AnyObject))
                output += introspector.dumpClass(fullClassName)
            }
        }
    }

    return output
}

/// Explore AXRuntime internals
func exploreAXRuntimeInternals() -> String {
    let introspector = ClassIntrospector.shared
    var output = ""

    output += "=" .padding(toLength: 60, withPad: "=", startingAt: 0) + "\n"
    output += "AXRUNTIME FRAMEWORK INTERNALS\n"
    output += "=" .padding(toLength: 60, withPad: "=", startingAt: 0) + "\n\n"

    // Load AXRuntime
    let handle = dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW)
    if handle == nil {
        output += "Failed to load AXRuntime\n"
        return output
    }
    output += "AXRuntime loaded successfully\n\n"

    // Find AX classes
    let axClasses = introspector.findClasses(matching: "AX")
        .filter { $0.hasPrefix("AX") }
        .sorted()

    output += ">>> AX Classes Found: \(axClasses.count) <<<\n\n"
    for cls in axClasses {
        output += "  - \(cls)\n"
    }
    output += "\n"

    // Dump key classes
    let keyClasses = ["AXUIElement", "AXElement", "AXElementFetcher", "AXSimpleRuntimeManager", "AXRemoteElement"]

    for className in keyClasses {
        if NSClassFromString(className) != nil {
            output += "-" .padding(toLength: 60, withPad: "-", startingAt: 0) + "\n"
            output += introspector.dumpClass(className)
        }
    }

    return output
}
