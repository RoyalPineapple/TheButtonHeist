#if canImport(UIKit)
#if DEBUG
import UIKit

extension Navigation {

    static func isObscuredByPresentation(view: UIView) -> Bool {
        guard let window = view.window,
              let rootVC = window.rootViewController else {
            return false
        }

        guard let topPresented = Self.topmostPresentedViewController(from: rootVC) else {
            return false
        }

        guard let viewVC = view.nearestViewController else {
            return false
        }
        return !viewVC.isDescendant(of: topPresented)
    }

    private static func topmostPresentedViewController(
        from root: UIViewController
    ) -> UIViewController? {
        var topPresented: UIViewController?

        var queue: [UIViewController] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()

            if let presented = current.presentedViewController {
                var top = presented
                while let next = top.presentedViewController {
                    top = next
                }
                topPresented = top
            }

            queue.append(contentsOf: current.children)
        }

        return topPresented
    }
}

extension UIView {

    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController { return viewController }
            responder = next
        }
        return nil
    }
}

extension UIViewController {

    func isDescendant(of ancestor: UIViewController) -> Bool {
        var queue: [UIViewController] = [ancestor]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current === self { return true }
            queue.append(contentsOf: current.children)
        }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
