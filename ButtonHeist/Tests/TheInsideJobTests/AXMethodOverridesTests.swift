#if canImport(UIKit)
import Testing
import UIKit
@testable import TheInsideJob

@Test("Plain object does not override accessibility action from NSObject")
func plainObjectDoesNotOverrideAccessibilityActionFromNSObject() {
    #expect(!AXMethodOverrides.object(
        NSObject(),
        overrides: #selector(NSObject.accessibilityPerformMagicTap)
    ))
}

@Test("Custom object overrides accessibility action from NSObject")
func customObjectOverridesAccessibilityActionFromNSObject() {
    #expect(AXMethodOverrides.object(
        CustomMagicTapObject(),
        overrides: #selector(NSObject.accessibilityPerformMagicTap)
    ))
}

@Test("Navigation controller default escape is base behavior")
func navigationControllerDefaultEscapeIsBaseBehavior() {
    #expect(!AXMethodOverrides.object(
        UINavigationController(),
        overrides: #selector(NSObject.accessibilityPerformEscape)
    ))
}

@Test("Navigation controller subclass escape override is detected")
func navigationControllerSubclassEscapeOverrideIsDetected() {
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
