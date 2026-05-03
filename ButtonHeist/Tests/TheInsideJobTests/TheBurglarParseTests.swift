#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class TheBurglarParseTests: XCTestCase {

    private var stash: TheStash!

    override func setUp() async throws {
        try await super.setUp()
        stash = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        stash = nil
        try await super.tearDown()
    }

    func testParseReturnsNilWhenNoAccessibleWindows() throws {
        let result = withNoTraversableWindows {
            stash.parse()
        }
        XCTAssertNil(result)
    }

    func testParseRestoresSearchBarHidingAfterParse() throws {
        let windowScene = try requireForegroundWindowScene()

        let contentVC = UIViewController()
        let searchController = UISearchController(searchResultsController: nil)
        contentVC.navigationItem.searchController = searchController
        contentVC.navigationItem.hidesSearchBarWhenScrolling = true

        let nav = UINavigationController(rootViewController: contentVC)
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 10
        window.rootViewController = nav
        window.frame = UIScreen.main.bounds
        window.isHidden = false

        defer {
            window.isHidden = true
        }

        XCTAssertTrue(contentVC.navigationItem.hidesSearchBarWhenScrolling)
        XCTAssertNotNil(stash.parse())
        XCTAssertTrue(
            contentVC.navigationItem.hidesSearchBarWhenScrolling,
            "parse() should restore hidesSearchBarWhenScrolling after temporary reveal"
        )
    }

    func testParseWrapsEachWindowWithSemanticGroupInMultiWindowMode() throws {
        let windowScene = try requireForegroundWindowScene()

        // Multi-window mode is only entered when no window is an overlay
        // (no modal flag, no level > .normal with a root VC, no presentation).
        // Use levels below .normal so the test windows coexist with the host
        // window without triggering overlay filtering.
        let levelA = UIWindow.Level(rawValue: -1001)
        let levelB = UIWindow.Level(rawValue: -1002)

        let windowA = makeWindow(windowScene: windowScene, level: levelA)
        let windowB = makeWindow(windowScene: windowScene, level: levelB)

        defer {
            windowA.isHidden = true
            windowB.isHidden = true
        }

        guard let result = stash.parse() else {
            XCTFail("Expected parse result for multi-window scene")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(levelA.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(levelB.rawValue)"))
    }

    func testParseIncludesPopoverContentSiblingAfterDismissRegion() throws {
        let windowScene = try requireForegroundWindowScene()

        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let backgroundLabel = UILabel(frame: CGRect(x: 20, y: 20, width: 260, height: 44))
        backgroundLabel.text = "Background Should Not Appear"
        backgroundLabel.isAccessibilityElement = true
        viewController.view.addSubview(backgroundLabel)

        let dismissRegion = UIView(frame: viewController.view.bounds.insetBy(dx: -1000, dy: -1000))
        dismissRegion.accessibilityViewIsModal = true
        dismissRegion.isAccessibilityElement = false
        dismissRegion.accessibilityIdentifier = "PopoverDismissRegion"
        viewController.view.addSubview(dismissRegion)

        let popoverButton = UIButton(type: .system)
        popoverButton.setTitle("Popover Action", for: .normal)
        popoverButton.frame = CGRect(x: 80, y: 120, width: 180, height: 44)
        viewController.view.addSubview(popoverButton)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 20
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false

        defer {
            window.isHidden = true
        }

        guard let result = stash.parse() else {
            XCTFail("Expected parse result for popover-style modal window")
            return
        }

        let labels = result.elements.compactMap(\.label)
        XCTAssertTrue(
            labels.contains("Popover Action"),
            "Popover content presented as a sibling after the dismiss region should be parsed"
        )
        XCTAssertFalse(
            labels.contains("Background Should Not Appear"),
            "Background siblings before the modal dismiss region should remain excluded"
        )
    }

    private func makeWindow(windowScene: UIWindowScene, level: UIWindow.Level) -> UIWindow {
        let vc = UIViewController()
        vc.view.backgroundColor = .white
        let label = UILabel()
        label.text = "Window \(Int(level.rawValue))"
        label.frame = CGRect(x: 20, y: 20, width: 200, height: 20)
        vc.view.addSubview(label)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = level
        window.rootViewController = vc
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        return window
    }

    private func semanticGroupValues(in hierarchy: [AccessibilityHierarchy]) -> [String] {
        var values: [String] = []
        for node in hierarchy {
            if case let .container(container, children) = node {
                if case let .semanticGroup(_, value, _) = container.type, let value {
                    values.append(value)
                }
                values.append(contentsOf: semanticGroupValues(in: children))
            }
        }
        return values
    }

    private func withNoTraversableWindows<T>(
        _ operation: () -> T
    ) -> T {
        let windows = stash.tripwire.getTraversableWindows().map(\.window)
        let originalHiddenStates = windows.map(\.isHidden)
        for window in windows {
            window.isHidden = true
        }
        defer {
            for (window, originalIsHidden) in zip(windows, originalHiddenStates) {
                window.isHidden = originalIsHidden
            }
        }
        return operation()
    }

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }
}

#endif
