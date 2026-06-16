#if canImport(UIKit)
#if DEBUG
import UIKit

/// Runtime dispatcher for UIKit accessibility actions.
///
/// The stash resolves live semantic targets; this type performs user intent on
/// the resolved live object.
@MainActor
final class AccessibilityActionDispatcher {

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

    func activate(_ liveTarget: TheStash.LiveActionTarget) -> ActivateOutcome {
        liveTarget.object.accessibilityActivate() ? .success : .refused
    }

    @discardableResult
    func increment(_ liveTarget: TheStash.LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityIncrement()
        return true
    }

    @discardableResult
    func decrement(_ liveTarget: TheStash.LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityDecrement()
        return true
    }

    func performCustomAction(named name: String, on liveTarget: TheStash.LiveActionTarget) -> CustomActionOutcome {
        performCustomAction(named: name, on: liveTarget.object)
    }

    private func performCustomAction(named name: String, on object: NSObject) -> CustomActionOutcome {
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
