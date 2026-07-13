#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import ThePlans

struct SafecrackerEditActions {

    @MainActor
    func perform(_ action: EditAction, on object: NSObject) -> Bool {
        UIApplication.shared.sendAction(action.selector, to: object, from: nil, for: nil)
    }

    /// Resign first responder, dismissing the keyboard if visible.
    /// Routes through the responder chain — no view hierarchy walk needed.
    @MainActor
    func resignFirstResponder() -> Bool {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @MainActor
    func resignFirstResponder(_ object: NSObject) -> Bool {
        guard let responder = object as? UIResponder else { return false }
        return responder.resignFirstResponder()
    }
}

extension EditAction {
    var selector: Selector {
        switch self {
        case .copy:      return #selector(UIResponderStandardEditActions.copy(_:))
        case .paste:     return #selector(UIResponderStandardEditActions.paste(_:))
        case .cut:       return #selector(UIResponderStandardEditActions.cut(_:))
        case .select:    return #selector(UIResponderStandardEditActions.select(_:))
        case .selectAll: return #selector(UIResponderStandardEditActions.selectAll(_:))
        case .delete:    return #selector(UIResponderStandardEditActions.delete(_:))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
