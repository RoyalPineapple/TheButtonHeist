#if canImport(UIKit)
#if DEBUG
import ObjectiveC.runtime
import UIKit

enum AXMethodOverrides {

    static func object(_ object: NSObject, overrides selector: Selector) -> Bool {
        Self.object(object, overrides: selector, relativeTo: defaultBaseClass(for: object))
    }

    static func object(_ object: NSObject, overrides selector: Selector, relativeTo baseClass: AnyClass) -> Bool {
        guard let objectClass = object_getClass(object),
              classIsSubclassOrSame(objectClass, baseClass)
        else { return false }

        var currentType: AnyClass? = objectClass
        while let candidate = currentType, candidate != baseClass {
            guard let superclass = class_getSuperclass(candidate) else { return false }

            let candidateImplementation = implementation(of: selector, in: candidate)
            let superclassImplementation = implementation(of: selector, in: superclass)
            if candidateImplementation != superclassImplementation {
                return candidateImplementation != nil
            }
            currentType = superclass
        }
        return false
    }

    private static func classIsSubclassOrSame(_ type: AnyClass, _ baseClass: AnyClass) -> Bool {
        var currentType: AnyClass? = type
        while let candidate = currentType {
            if candidate == baseClass {
                return true
            }
            currentType = class_getSuperclass(candidate)
        }
        return false
    }

    private static func implementation(of selector: Selector, in type: AnyClass) -> IMP? {
        class_getInstanceMethod(type, selector).map(method_getImplementation)
    }

    private static func defaultBaseClass(for object: NSObject) -> AnyClass {
        switch object {
        case is UINavigationController:
            return UINavigationController.self
        case is UITabBarController:
            return UITabBarController.self
        case is UIViewController:
            return UIViewController.self
        case is UIControl:
            return UIControl.self
        case is UIView:
            return UIView.self
        case is UIResponder:
            return UIResponder.self
        case is UIAccessibilityElement:
            return UIAccessibilityElement.self
        default:
            return NSObject.self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
