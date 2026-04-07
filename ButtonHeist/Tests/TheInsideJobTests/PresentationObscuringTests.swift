#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class PresentationObscuringTests: XCTestCase {

    // MARK: - UIView.nearestViewController

    func testNearestViewControllerFindsOwningVC() {
        let viewController = UIViewController()
        _ = viewController.view
        let childView = UIView()
        viewController.view.addSubview(childView)

        XCTAssertIdentical(childView.nearestViewController, viewController)
    }

    func testNearestViewControllerReturnsNilForOrphanView() {
        let orphan = UIView()
        XCTAssertNil(orphan.nearestViewController)
    }

    func testNearestViewControllerFindsNestedViewOwner() {
        let viewController = UIViewController()
        _ = viewController.view
        let wrapper = UIView()
        let nested = UIView()
        wrapper.addSubview(nested)
        viewController.view.addSubview(wrapper)

        XCTAssertIdentical(nested.nearestViewController, viewController)
    }

    // MARK: - UIViewController.isDescendant(of:)

    func testIsDescendantOfSelf() {
        let viewController = UIViewController()
        XCTAssertTrue(viewController.isDescendant(of: viewController))
    }

    func testIsDescendantOfParent() {
        let parent = UIViewController()
        let child = UIViewController()
        parent.addChild(child)
        child.didMove(toParent: parent)

        XCTAssertTrue(child.isDescendant(of: parent))
    }

    func testIsNotDescendantOfUnrelatedVC() {
        let viewControllerA = UIViewController()
        let viewControllerB = UIViewController()

        XCTAssertFalse(viewControllerA.isDescendant(of: viewControllerB))
    }

    func testIsDescendantThroughNavigationController() {
        let root = UIViewController()
        let navigationController = UINavigationController(rootViewController: root)

        XCTAssertTrue(root.isDescendant(of: navigationController))
    }

    func testIsDescendantThroughTabBarController() {
        let child = UIViewController()
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [child]

        XCTAssertTrue(child.isDescendant(of: tabBarController))
    }

    func testIsDescendantDeeplyNested() {
        let grandparent = UIViewController()
        let parent = UIViewController()
        let child = UIViewController()
        grandparent.addChild(parent)
        parent.addChild(child)

        XCTAssertTrue(child.isDescendant(of: grandparent))
        XCTAssertTrue(child.isDescendant(of: parent))
        XCTAssertFalse(grandparent.isDescendant(of: child))
    }

    // MARK: - isObscuredByPresentation

    func testViewWithNoWindowIsNotObscured() {
        let view = UIView()
        XCTAssertFalse(TheBrains.isObscuredByPresentation(view: view))
    }

    func testViewInWindowWithNoPresentationIsNotObscured() {
        let window = UIWindow()
        let rootVC = UIViewController()
        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        _ = rootVC.view

        let testView = UIView()
        rootVC.view.addSubview(testView)

        XCTAssertFalse(TheBrains.isObscuredByPresentation(view: testView))

        window.isHidden = true
    }

    // MARK: - ScreenManifest skippedObscuredContainers

    func testScreenManifestSkippedObscuredContainersDefaultsToZero() {
        let manifest = TheBrains.ScreenManifest()
        XCTAssertEqual(manifest.skippedObscuredContainers, 0)
    }

    func testScreenManifestSkippedObscuredContainersIncrements() {
        var manifest = TheBrains.ScreenManifest()
        manifest.skippedObscuredContainers += 1
        manifest.skippedObscuredContainers += 1
        XCTAssertEqual(manifest.skippedObscuredContainers, 2)
    }
}

#endif
