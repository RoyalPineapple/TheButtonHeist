#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheTripwireWindowTraversalTests: XCTestCase {

    func testFilterReturnsNoRootsForNoWindows() {
        XCTAssertTrue(TheTripwire.filterToAccessibleWindows([]).isEmpty)
    }

    func testFilterKeepsEveryAppWindowInInputOrder() {
        let elevatedKey = makeWindow(
            level: .alert + 1,
            rootViewController: UIViewController(),
            type: AlwaysKeyWindow.self
        )
        elevatedKey.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let windows = [
            makeWindow(level: .alert, rootViewController: UIViewController()),
            elevatedKey,
            makeWindow(level: .normal, rootViewController: nil),
            makeWindow(level: .normal - 1, rootViewController: UIViewController()),
        ]

        let result = TheTripwire.filterToAccessibleWindows(windows.map(windowRoot))

        XCTAssertTrue(elevatedKey.isKeyWindow)
        assertWindowOrder(result, equals: windows)
        XCTAssertTrue(result[2].rootView === windows[2])
    }

    func testFilterDropsOnlyPassthroughWindows() {
        let keyboard = makeWindow(level: .statusBar, rootViewController: UIViewController())
        let textEffects = makeWindow(level: .alert + 1, rootViewController: UIViewController())
        let overlay = makeWindow(level: .alert, rootViewController: UIViewController())
        let app = makeWindow(level: .normal, rootViewController: UIViewController())
        let lower = makeWindow(level: .normal - 1, rootViewController: UIViewController())
        let passthroughs = [keyboard, textEffects]
        let isPassthrough: (UIWindow) -> Bool = { candidate in
            passthroughs.contains { $0 === candidate }
        }
        let cases = [
            (
                name: "mixed window stack",
                input: [keyboard, overlay, textEffects, app, lower],
                expected: [overlay, app, lower]
            ),
            (name: "only passthroughs", input: passthroughs, expected: []),
        ]

        for testCase in cases {
            let result = TheTripwire.filterToAccessibleWindows(
                testCase.input.map(windowRoot),
                isPassthrough: isPassthrough
            )
            assertWindowOrder(result, equals: testCase.expected, message: testCase.name)
        }
    }

    func testFilterUsesDeepestPresentedViewForEachAppWindow() {
        let root = StubViewController()
        let middle = StubViewController()
        let deepest = UIViewController()
        root.presented = middle
        middle.presented = deepest
        let base = makeWindow(level: .normal, rootViewController: root)
        let overlay = makeWindow(level: .alert, rootViewController: UIViewController())

        let result = TheTripwire.filterToAccessibleWindows([overlay, base].map(windowRoot))

        assertWindowOrder(result, equals: [overlay, base])
        XCTAssertTrue(result[0].rootView === overlay.rootViewController?.view)
        XCTAssertTrue(result[1].rootView === deepest.view)
    }

    func testTopmostViewControllerUsesStandardContainersOnly() {
        let navigationTop = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(navigationTop, animated: false)

        let selectedTab = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [UIViewController(), selectedTab]
        tabs.selectedIndex = 1

        let arbitraryParent = UIViewController()
        let childNavigation = UINavigationController(rootViewController: UIViewController())
        arbitraryParent.addChild(childNavigation)
        arbitraryParent.view.addSubview(childNavigation.view)
        childNavigation.didMove(toParent: arbitraryParent)

        let cases: [(name: String, root: UIViewController, expected: UIViewController)] = [
            ("navigation stack", navigation, navigationTop),
            ("selected tab", tabs, selectedTab),
            ("arbitrary child container", arbitraryParent, arbitraryParent),
        ]

        for testCase in cases {
            let window = makeWindow(level: .normal, rootViewController: testCase.root)
            let result = TheTripwire.topmostViewController(in: [windowRoot(window)])
            XCTAssertTrue(result === testCase.expected, testCase.name)
        }
    }

    func testTopmostViewControllerSkipsPassthroughAndWalksPresentedChain() {
        let root = StubViewController()
        let presented = UIViewController()
        root.presented = presented
        let keyboard = makeWindow(level: .alert, rootViewController: UIViewController())
        let app = makeWindow(level: .normal, rootViewController: root)

        let result = TheTripwire.topmostViewController(
            in: [keyboard, app].map(windowRoot),
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertTrue(result === presented)
    }

    func testTopmostViewControllerReturnsNilWhenOnlyPassthroughsExist() {
        let keyboard = makeWindow(level: .alert, rootViewController: UIViewController())

        let result = TheTripwire.topmostViewController(
            in: [windowRoot(keyboard)],
            isPassthrough: { _ in true }
        )

        XCTAssertNil(result)
    }

    func testKeyboardTransitionsPreserveTopmostViewController() {
        let appViewController = UIViewController()
        let app = makeWindow(level: .normal, rootViewController: appViewController)
        let keyboard = makeWindow(level: .alert, rootViewController: UIViewController())
        let appOnly = [windowRoot(app)]
        let withKeyboard = [windowRoot(keyboard), windowRoot(app)]
        let phases = [appOnly, withKeyboard, appOnly]

        for windows in phases {
            let result = TheTripwire.topmostViewController(
                in: windows,
                isPassthrough: { $0 === keyboard }
            )
            XCTAssertTrue(result === appViewController)
        }
    }

    private final class StubViewController: UIViewController {
        var presented: UIViewController?
        override var presentedViewController: UIViewController? { presented }
    }

    private final class AlwaysKeyWindow: UIWindow {
        override var isKeyWindow: Bool { true }
    }

    private func makeWindow(
        level: UIWindow.Level,
        rootViewController: UIViewController?
    ) -> UIWindow {
        makeWindow(level: level, rootViewController: rootViewController, type: UIWindow.self)
    }

    private func makeWindow<Window: UIWindow>(
        level: UIWindow.Level,
        rootViewController: UIViewController?,
        type: Window.Type
    ) -> Window {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return Window()
        }
        let window = Window(windowScene: scene)
        window.windowLevel = level
        window.frame = UIScreen.main.bounds
        window.rootViewController = rootViewController
        return window
    }

    private func windowRoot(_ window: UIWindow) -> TheTripwire.WindowTraversalRoot {
        TheTripwire.WindowTraversalRoot(window: window, rootView: window)
    }

    private func assertWindowOrder(
        _ roots: [TheTripwire.WindowTraversalRoot],
        equals windows: [UIWindow],
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(roots.count, windows.count, message, file: file, line: line)
        for (root, window) in zip(roots, windows) {
            XCTAssertTrue(root.window === window, message, file: file, line: line)
        }
    }
}

#endif // canImport(UIKit)
