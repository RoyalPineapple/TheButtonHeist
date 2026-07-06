#if canImport(UIKit)
import Testing
import UIKit
@testable import TheInsideJob

@Test func `Plain object does not override accessibility action from NSObject`() {
    #expect(!AXMethodOverrides.object(
        NSObject(),
        overrides: #selector(NSObject.accessibilityPerformMagicTap)
    ))
}

@Test func `Custom object overrides accessibility action from NSObject`() {
    #expect(AXMethodOverrides.object(
        CustomMagicTapObject(),
        overrides: #selector(NSObject.accessibilityPerformMagicTap)
    ))
}

@Test func `Navigation controller default escape is base behavior`() {
    #expect(!AXMethodOverrides.object(
        UINavigationController(),
        overrides: #selector(NSObject.accessibilityPerformEscape)
    ))
}

@Test func `Navigation controller subclass escape override is detected`() {
    #expect(AXMethodOverrides.object(
        CustomNavigationController(),
        overrides: #selector(NSObject.accessibilityPerformEscape)
    ))
}

private final class CustomMagicTapObject: NSObject {
    override func accessibilityPerformMagicTap() -> Bool {
        true
    }
}

private final class CustomNavigationController: UINavigationController {
    override func accessibilityPerformEscape() -> Bool {
        true
    }
}
#endif
