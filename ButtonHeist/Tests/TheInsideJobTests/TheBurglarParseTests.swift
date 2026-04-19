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

        let levelA = UIWindow.Level(rawValue: 4321)
        let levelB = UIWindow.Level(rawValue: 4322)

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

    func testParseEmitsNavigationBarContainerForUINavigationBar() throws {
        let windowScene = try requireForegroundWindowScene()

        let contentVC = UIViewController()
        contentVC.title = "Nav Bar Detection Test"
        let nav = UINavigationController(rootViewController: contentVC)
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 20
        window.rootViewController = nav
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer { window.isHidden = true }

        let result = try XCTUnwrap(stash.parse())
        stash.apply(result)

        let containers = stash.currentHierarchy.flattenToContainers()
        let navBarContainers = containers.filter { container in
            if case .navigationBar = container.type { return true }
            return false
        }
        XCTAssertFalse(
            navBarContainers.isEmpty,
            "Parser must emit a ContainerType.navigationBar for a live UINavigationBar. Got containers: \(containers.map { "\($0.type)" })"
        )
        if let navBar = navBarContainers.first {
            XCTAssertGreaterThan(
                navBar.frame.height, 0,
                "Nav bar container must carry a non-empty frame"
            )
        }
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
