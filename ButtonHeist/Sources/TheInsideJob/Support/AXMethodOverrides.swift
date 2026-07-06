#if canImport(UIKit)
#if DEBUG
import Darwin
import ObjectiveC.runtime
import UIKit

enum AXMethodOverrides {

    static func object(_ object: NSObject, overrides selector: Selector) -> Bool {
        object(object, overrides: selector, relativeTo: defaultBaseClass(for: object))
    }

    static func object(_ object: NSObject, overrides selector: Selector, relativeTo baseClass: AnyClass) -> Bool {
        guard classIsSubclassOrSame(type(of: object), baseClass) else { return false }
        guard let overrideImplementation = declaredOverrideImplementation(
            of: selector,
            in: type(of: object),
            stoppingBefore: baseClass
        ) else { return false }
        guard let baseImplementation = implementation(of: selector, in: baseClass) else {
            return true
        }
        return overrideImplementation != baseImplementation
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

    private static func declaredOverrideImplementation(
        of selector: Selector,
        in type: AnyClass,
        stoppingBefore baseClass: AnyClass
    ) -> IMP? {
        var currentType: AnyClass? = type
        while let candidate = currentType, candidate != baseClass {
            if let implementation = declaredImplementation(of: selector, in: candidate) {
                return implementation
            }
            currentType = class_getSuperclass(candidate)
        }
        return nil
    }

    private static func declaredImplementation(of selector: Selector, in type: AnyClass) -> IMP? {
        var methodCount: UInt32 = 0
        guard let methods = class_copyMethodList(type, &methodCount) else { return nil }
        defer { free(methods) }

        for index in 0..<Int(methodCount) {
            let method = methods[index]
            if method_getName(method) == selector {
                return method_getImplementation(method)
            }
        }
        return nil
    }

    private static func implementation(of selector: Selector, in type: AnyClass) -> IMP? {
        var currentType: AnyClass? = type
        while let candidate = currentType {
            if let method = class_getInstanceMethod(candidate, selector) {
                return method_getImplementation(method)
            }
            currentType = class_getSuperclass(candidate)
        }
        return nil
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
