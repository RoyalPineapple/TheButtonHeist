#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

private let accessibilityArmingLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

enum AccessibilityEnvironmentKey: String, Sendable {
    case iPhoneSimulatorRoot = "IPHONE_SIMULATOR_ROOT"
}

private extension Dictionary where Key == String, Value == String {
    subscript(_ key: AccessibilityEnvironmentKey) -> String? {
        self[key.rawValue]
    }
}

// MARK: - Accessibility Arming

/// Arms the accessibility runtime so the live accessibility tree is populated.
///
/// SwiftUI (and parts of UIKit) only build their accessibility tree when an assistive technology is
/// active. The AccessibilitySnapshot parser ships its own enabler (`ASAccessibilityEnabler`, a
/// legacy `_AXSSetAutomationEnabled` toggle in an ObjC `+load`), but its framework is not
/// load-time-linked into Button Heist — so the `+load` never fires — and the legacy automation
/// switch no longer populates the tree on recent iOS. Without this, `get_interface` returns zero
/// elements on a freshly launched app until accessibility is enabled out-of-band.
///
/// This toggles the current SPI (`_AXSSetApplicationAccessibilityEnabled`) and the legacy one
/// (`_AXSSetAutomationEnabled`) directly, covering the deployment range. Both calls are idempotent,
/// so arming when an external harness already enabled accessibility is harmless. DEBUG-only; called
/// once during server auto-start.
func armApplicationAccessibility(environment: [String: String] = ProcessInfo.processInfo.environment) {
    let path = libAccessibilityPath(environment: environment)
    guard let handle = dlopen(path, RTLD_LOCAL) else {
        accessibilityArmingLogger.error("Could not dlopen libAccessibility at \(path, privacy: .public)")
        return
    }

    setAccessibilityFlag(handle, symbol: "_AXSSetApplicationAccessibilityEnabled")
    setAccessibilityFlag(handle, symbol: "_AXSSetAutomationEnabled")
}

/// Computes the path to `libAccessibility.dylib`, prefixing the simulator root when running in a
/// simulator (where system dylibs live under `IPHONE_SIMULATOR_ROOT`).
func libAccessibilityPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
    let dylib = "/usr/lib/libAccessibility.dylib"
    guard let simulatorRoot = environment[.iPhoneSimulatorRoot] else {
        return dylib
    }
    return (simulatorRoot as NSString).appendingPathComponent(dylib)
}

// MARK: - Private Helpers

private func setAccessibilityFlag(_ handle: UnsafeMutableRawPointer, symbol: String) {
    guard let pointer = dlsym(handle, symbol) else {
        accessibilityArmingLogger.debug("\(symbol, privacy: .public) not found in libAccessibility")
        return
    }
    typealias SetEnabledFunction = @convention(c) (Int32) -> Void
    let setEnabled = unsafeBitCast(pointer, to: SetEnabledFunction.self)
    setEnabled(1)
    accessibilityArmingLogger.info("Armed accessibility via \(symbol, privacy: .public)")
}

#endif // DEBUG
#endif // canImport(UIKit)
