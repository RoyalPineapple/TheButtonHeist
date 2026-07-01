#if canImport(UIKit)
#if DEBUG
import Darwin
import Foundation
import MachO

/// Central inventory and dynamic-loading primitives for private Apple SPI used by TheInsideJob.
///
/// Keep private C symbols, framework install names, `dlopen`, `dlsym`, and
/// unsafe C function casts in this one static namespace. Callers still own their
/// domain-specific behavior on top of these primitives.
enum ButtonHeistPrivateSPI {

    enum SPISymbolName: String {
        case accessibilityAddNotificationCallback = "AXAddNotificationCallback"
        case accessibilityRemoveNotificationCallback = "AXRemoveNotificationCallback"
        case accessibilitySetApplicationAccessibilityEnabled = "_AXSSetApplicationAccessibilityEnabled"
        case accessibilitySetAutomationEnabled = "_AXSSetAutomationEnabled"
        case accessibilitySetUnitTestMode = "_AXSSetInUnitTestMode"
        case ioHIDEventAppendEvent = "IOHIDEventAppendEvent"
        case ioHIDEventCreateDigitizerEvent = "IOHIDEventCreateDigitizerEvent"
        case ioHIDEventCreateDigitizerFingerEventWithQuality = "IOHIDEventCreateDigitizerFingerEventWithQuality"
        case ioHIDEventSetFloatValue = "IOHIDEventSetFloatValue"
    }

    enum SPIFrameworkPath: String, CaseIterable {
        case ioKit = "/System/Library/Frameworks/IOKit.framework/IOKit"
        case libAccessibility = "/usr/lib/libAccessibility.dylib"
        case uiAccessibility = "/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility"
        case uiKit = "/System/Library/Frameworks/UIKit.framework/UIKit"
        case uiKitCore = "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"

        static let accessibilityNotificationCallbackFallbackSearchOrder: [SPIFrameworkPath] = [
            .uiAccessibility,
            .uiKitCore,
            .uiKit,
        ]

        var usesSimulatorRoot: Bool {
            self == .libAccessibility
        }
    }

    static func path(
        _ frameworkPath: SPIFrameworkPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        guard frameworkPath.usesSimulatorRoot,
              let simulatorRoot = environment[AccessibilityEnvironmentKey.iPhoneSimulatorRoot.rawValue]
        else {
            return frameworkPath.rawValue
        }
        return (simulatorRoot as NSString).appendingPathComponent(frameworkPath.rawValue)
    }

    static func open(
        _ frameworkPath: SPIFrameworkPath,
        flags: Int32 = RTLD_NOW | RTLD_LOCAL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UnsafeMutableRawPointer? {
        openLibrary(at: path(frameworkPath, environment: environment), flags: flags)
    }

    static func openLibrary(at path: String, flags: Int32 = RTLD_NOW | RTLD_LOCAL) -> UnsafeMutableRawPointer? {
        dlopen(path, flags)
    }

    static func processHandle(flags: Int32 = RTLD_NOW) -> UnsafeMutableRawPointer? {
        dlopen(nil, flags)
    }

    static func symbol(_ name: SPISymbolName, in handle: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        dlsym(handle, name.rawValue)
    }

    static func function<Function>(
        _ name: SPISymbolName,
        in handle: UnsafeMutableRawPointer,
        as type: Function.Type
    ) -> Function? {
        guard let symbol = symbol(name, in: handle) else {
            return nil
        }
        return cast(symbol, to: type)
    }

    static func function<Function>(
        _ name: SPISymbolName,
        in frameworkPath: SPIFrameworkPath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        as type: Function.Type
    ) -> Function? {
        guard let symbol = resolveSymbol(name, in: frameworkPath, environment: environment) else {
            return nil
        }
        return cast(symbol, to: type)
    }

    static func resolveSymbol(
        _ name: SPISymbolName,
        in frameworkPath: SPIFrameworkPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UnsafeMutableRawPointer? {
        if let processHandle = processHandle(),
           let symbol = symbol(name, in: processHandle) {
            return symbol
        }

        guard let handle = open(frameworkPath, environment: environment),
              let symbol = symbol(name, in: handle)
        else {
            return nil
        }
        return symbol
    }

    static func loadedImagePaths() -> [String] {
        var paths: [String] = []
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index) else { continue }
            paths.append(String(cString: name))
        }
        return uniquePreservingOrder(paths)
    }

    static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func cast<Function>(_ symbol: UnsafeMutableRawPointer, to type: Function.Type) -> Function {
        unsafeBitCast(symbol, to: type)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
