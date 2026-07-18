#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

/// Runtime dispatcher for UIKit accessibility actions.
///
/// The vault resolves live semantic targets; this type performs user intent on
/// the resolved live object.
@MainActor
final class AccessibilityActionDispatcher {

    enum ActivateOutcome: Sendable {
        case success
        case objectDeallocated
        case refused
    }

    enum CustomActionOutcome: Sendable {
        case succeeded
        case declined
        case deallocated
        case noSuchAction
    }

    enum ScreenActionOutcome: Equatable, Sendable {
        case succeeded(handler: String)
        case noHandler
    }

    func activate(_ liveTarget: TheVault.LiveActionTarget) -> ActivateOutcome {
        liveTarget.object.accessibilityActivate() ? .success : .refused
    }

    @discardableResult
    func increment(_ liveTarget: TheVault.LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityIncrement()
        return true
    }

    @discardableResult
    func decrement(_ liveTarget: TheVault.LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityDecrement()
        return true
    }

    func performCustomAction(named name: CustomActionName, on liveTarget: TheVault.LiveActionTarget) -> CustomActionOutcome {
        performCustomAction(named: name, on: liveTarget.object)
    }

    func needsPreDispatchRefresh(named name: CustomActionName, on liveTarget: TheVault.LiveActionTarget) -> Bool {
        guard !(liveTarget.object is UIView),
              let action = liveTarget.object.accessibilityCustomActions?.first(where: { $0.name == name.rawValue })
        else { return false }
        return action.actionHandler != nil
    }

    private func performCustomAction(named name: CustomActionName, on object: NSObject) -> CustomActionOutcome {
        guard let action = object.accessibilityCustomActions?
            .first(where: { $0.name == name.rawValue }) else {
            return .noSuchAction
        }
        if let handler = action.actionHandler {
            return handler(action) ? .succeeded : .declined
        }
        if let receiver = action.target as? NSObject {
            guard let message = ObjCRuntime.message(.accessibilityCustomAction(action.selector), to: receiver) else {
                return .noSuchAction
            }
            return message.call(action) ? .succeeded : .declined
        }
        return .noSuchAction
    }

    func dismiss(startingAt object: NSObject?, fallback: UIResponder?) -> ScreenActionOutcome {
        perform(.dismiss, startingAt: object, fallback: fallback)
    }

    func magicTap(startingAt object: NSObject?, fallback: UIResponder?) -> ScreenActionOutcome {
        perform(.magicTap, startingAt: object, fallback: fallback)
    }

    func availableScreenActions(startingAt object: NSObject?, fallback: UIResponder?) -> [ScreenAction] {
        let candidates = actionCandidates(startingAt: object, fallback: fallback)
        return ResponderAction.allCases.compactMap { action in
            candidates.contains { Self.canHandle(action, object: $0) } ? action.screenAction : nil
        }
    }

    private func perform(
        _ action: ResponderAction,
        startingAt object: NSObject?,
        fallback: UIResponder?
    ) -> ScreenActionOutcome {
        for candidate in actionCandidates(startingAt: object, fallback: fallback) where action.perform(on: candidate) {
            return .succeeded(handler: Self.handlerName(candidate))
        }
        return .noHandler
    }

    private func actionCandidates(startingAt object: NSObject?, fallback: UIResponder?) -> [NSObject] {
        var candidates: [NSObject] = []
        var seen: Set<ObjectIdentifier> = []

        func append(_ object: NSObject) {
            if seen.insert(ObjectIdentifier(object)).inserted {
                candidates.append(object)
            }
        }

        func appendResponderChain(from responder: UIResponder?) {
            var current = responder
            while let responder = current {
                append(responder)
                current = responder.next
            }
        }

        func appendAccessibilityContainerChain(from object: NSObject) {
            var current = Self.accessibilityContainer(of: object)
            while let container = current {
                if let responder = container as? UIResponder {
                    appendResponderChain(from: responder)
                    return
                }
                append(container)
                current = Self.accessibilityContainer(of: container)
            }
        }

        if let object {
            append(object)
            if let responder = object as? UIResponder {
                appendResponderChain(from: responder.next)
            } else {
                appendAccessibilityContainerChain(from: object)
            }
        }
        appendResponderChain(from: fallback)
        return candidates
    }

    private static func accessibilityContainer(of object: NSObject) -> NSObject? {
        if let element = object as? UIAccessibilityElement {
            return element.accessibilityContainer as? NSObject
        }
        return ObjCRuntime.get(.accessibilityContainer, from: object)
    }

    private static func canHandle(_ action: ResponderAction, object: NSObject) -> Bool {
        switch action {
        case .dismiss:
            if hasDismissState(object) { return true }
            return overridesAccessibilityAction(action, object: object)
        case .magicTap:
            return overridesAccessibilityAction(action, object: object)
        }
    }

    private static func hasDismissState(_ object: NSObject) -> Bool {
        if let navigationController = object as? UINavigationController {
            return navigationController.viewControllers.count > 1
                || navigationController.presentedViewController != nil
                || navigationController.presentingViewController != nil
        }
        guard let viewController = object as? UIViewController else { return false }
        if viewController.presentedViewController != nil || viewController.presentingViewController != nil {
            return true
        }
        guard let navigationController = viewController.navigationController else { return false }
        return navigationController.viewControllers.count > 1
            && navigationController.topViewController === viewController
    }

    private static func overridesAccessibilityAction(_ action: ResponderAction, object: NSObject) -> Bool {
        AXMethodOverrides.object(object, overrides: action.selector)
    }

    private static func handlerName(_ object: NSObject) -> String {
        NSStringFromClass(type(of: object)).split(separator: ".").last.map(String.init)
            ?? String(describing: type(of: object))
    }

    private enum ResponderAction: CaseIterable {
        case dismiss
        case magicTap

        var selector: Selector {
            switch self {
            case .dismiss:
                return #selector(NSObject.accessibilityPerformEscape)
            case .magicTap:
                return #selector(NSObject.accessibilityPerformMagicTap)
            }
        }

        var screenAction: ScreenAction {
            switch self {
            case .dismiss:
                return .dismiss
            case .magicTap:
                return .magicTap
            }
        }

        @MainActor func perform(on object: NSObject) -> Bool {
            switch self {
            case .dismiss:
                return object.accessibilityPerformEscape()
            case .magicTap:
                return object.accessibilityPerformMagicTap()
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
