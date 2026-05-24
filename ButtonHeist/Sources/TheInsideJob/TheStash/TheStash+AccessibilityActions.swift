#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Accessibility Actions

extension TheStash {

    /// Outcome of `activate(_:)`.
    enum ActivateOutcome {
        case success
        case objectDeallocated
        case refused
    }

    enum CustomActionOutcome {
        case succeeded
        case declined
        case deallocated
        case noSuchAction
    }

    func activate(_ liveTarget: LiveActionTarget) -> ActivateOutcome {
        liveTarget.object.accessibilityActivate() ? .success : .refused
    }

    @discardableResult
    func increment(_ liveTarget: LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityIncrement()
        return true
    }

    @discardableResult
    func decrement(_ liveTarget: LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityDecrement()
        return true
    }

    func performCustomAction(named name: String, on liveTarget: LiveActionTarget) -> CustomActionOutcome {
        performCustomAction(named: name, on: liveTarget.object)
    }

    func performCustomAction(named name: String, on containerTarget: LiveContainerTarget) -> CustomActionOutcome {
        performCustomAction(named: name, on: containerTarget.object)
    }
}

private extension TheStash {

    func performCustomAction(named name: String, on object: NSObject) -> CustomActionOutcome {
        guard let action = object.accessibilityCustomActions?
            .first(where: { $0.name == name }) else {
            return .noSuchAction
        }
        if let handler = action.actionHandler {
            return handler(action) ? .succeeded : .declined
        }
        if let target = action.target {
            _ = (target as AnyObject).perform(action.selector, with: action)
            return .succeeded
        }
        return .noSuchAction
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
