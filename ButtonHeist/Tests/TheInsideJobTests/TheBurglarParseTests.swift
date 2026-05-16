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

    func testParseDoesNotMutateSearchBarHiding() throws {
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
            "parse() should not change hidesSearchBarWhenScrolling"
        )
    }

    func testParseWrapsEachWindowWithSemanticGroupInMultiWindowMode() throws {
        let windowScene = try requireForegroundWindowScene()

        let levelA = UIWindow.Level(rawValue: 1999)
        let levelB = UIWindow.Level.normal

        let result = withNoTraversableWindows {
            let windowA = makeWindow(windowScene: windowScene, level: levelA)
            let windowB = makeWindow(windowScene: windowScene, level: levelB, makeKey: true)

            defer {
                windowA.isHidden = true
                windowB.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for multi-window scene")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(levelA.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(levelB.rawValue)"))
    }

    func testParseIncludesBaseWindowWhenElevatedNonModalWindowIsPresent() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let base = makeWindow(windowScene: windowScene, level: .normal)

            let overlayViewController = UIViewController()
            overlayViewController.view.backgroundColor = .clear
            let overlayLabel = UILabel(frame: CGRect(x: 20, y: 60, width: 260, height: 44))
            overlayLabel.text = "Reader Overlay"
            overlayViewController.view.addSubview(overlayLabel)

            let overlay = UIWindow(windowScene: windowScene)
            overlay.windowLevel = .alert - 1
            overlay.rootViewController = overlayViewController
            overlay.frame = UIScreen.main.bounds
            overlay.isHidden = false

            defer {
                base.isHidden = true
                overlay.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result with base and elevated non-modal windows")
            return
        }

        let labels = result.hierarchy.sortedElements.compactMap(\.label)
        XCTAssertTrue(
            labels.contains("Window \(Int(UIWindow.Level.normal.rawValue))"),
            "Elevated non-modal windows should not hide the base app window"
        )
        XCTAssertTrue(
            labels.contains("Reader Overlay"),
            "Elevated non-modal windows should contribute their own accessible content"
        )
    }

    func testParseStopsAtKeyWindowWhenNoModalBoundaryAppears() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let overlay = makeWindow(windowScene: windowScene, level: .alert)
            let keyWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)
            let lower = makeWindow(windowScene: windowScene, level: .normal - 1)

            defer {
                overlay.isHidden = true
                keyWindow.isHidden = true
                lower.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for windows through key window")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.alert.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \((UIWindow.Level.normal - 1).rawValue)"))
    }

    func testParseStopsBeforeKeyWindowWhenModalBoundaryAppearsAboveIt() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let modalOverlay = makeWindow(windowScene: windowScene, level: .alert)
            addModalBoundary(to: modalOverlay)

            let keyWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)

            defer {
                modalOverlay.isHidden = true
                keyWindow.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for modal overlay")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.alert.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testParseIgnoresModalBoundaryBelowKeyWindow() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let lowerModal = makeWindow(windowScene: windowScene, level: .normal)
            addModalBoundary(to: lowerModal)
            let keyWindow = makeWindow(windowScene: windowScene, level: .alert, makeKey: true)

            defer {
                keyWindow.isHidden = true
                lowerModal.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for key window above modal")
            return
        }

        let labels = result.hierarchy.sortedElements.compactMap(\.label)
        XCTAssertTrue(labels.contains("Window \(Int(UIWindow.Level.alert.rawValue))"))
        XCTAssertFalse(labels.contains("Window \(Int(UIWindow.Level.normal.rawValue))"))
    }

    func testParseStopsAtFrontmostModalBoundary() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let upperModal = makeWindow(windowScene: windowScene, level: UIWindow.Level(rawValue: 2000))
            addModalBoundary(to: upperModal)
            let lowerModal = makeWindow(windowScene: windowScene, level: UIWindow.Level(rawValue: 100))
            addModalBoundary(to: lowerModal)
            let keyWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)

            defer {
                upperModal.isHidden = true
                lowerModal.isHidden = true
                keyWindow.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for stacked modal windows")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: 2000.0"))
        XCTAssertFalse(values.contains("windowLevel: 100.0"))
        XCTAssertFalse(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testParseKeepsOverlaysAboveModalBoundaryAndDropsLowerWindows() throws {
        let windowScene = try requireForegroundWindowScene()
        let modalLevel = UIWindow.Level(rawValue: 100)

        let result = withNoTraversableWindows {
            let overlayA = makeWindow(windowScene: windowScene, level: UIWindow.Level(rawValue: 2000))
            let overlayB = makeWindow(windowScene: windowScene, level: UIWindow.Level(rawValue: 1999))
            let modalWindow = makeWindow(windowScene: windowScene, level: modalLevel)
            addModalBoundary(to: modalWindow)
            let keyWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)

            defer {
                overlayA.isHidden = true
                overlayB.isHidden = true
                modalWindow.isHidden = true
                keyWindow.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for overlay and modal windows")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: 2000.0"))
        XCTAssertTrue(values.contains("windowLevel: 1999.0"))
        XCTAssertTrue(values.contains("windowLevel: \(modalLevel.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testParseTreatsDeepModalSubviewAsWindowBoundary() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let overlay = makeWindow(windowScene: windowScene, level: .alert)
            let modalWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)
            addModalBoundary(to: modalWindow, nestingDepth: 3)
            let lower = makeWindow(windowScene: windowScene, level: .normal - 1)

            defer {
                overlay.isHidden = true
                modalWindow.isHidden = true
                lower.isHidden = true
            }

            return stash.parse()
        }

        guard let result else {
            XCTFail("Expected parse result for deep modal boundary")
            return
        }

        let values = semanticGroupValues(in: result.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.alert.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \((UIWindow.Level.normal - 1).rawValue)"))
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

        let labels = result.hierarchy.sortedElements.compactMap(\.label)
        XCTAssertTrue(
            labels.contains("Popover Action"),
            "Popover content presented as a sibling after the dismiss region should be parsed"
        )
        XCTAssertFalse(
            labels.contains("Background Should Not Appear"),
            "Background siblings before the modal dismiss region should remain excluded"
        )
    }

    private func makeWindow(
        windowScene: UIWindowScene,
        level: UIWindow.Level,
        makeKey: Bool = false
    ) -> UIWindow {
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
        if makeKey {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = false
        }
        return window
    }

    private func addModalBoundary(to window: UIWindow, nestingDepth: Int = 0) {
        var parent = window.rootViewController?.view ?? window
        for _ in 0..<nestingDepth {
            let wrapper = UIView(frame: parent.bounds)
            parent.addSubview(wrapper)
            parent = wrapper
        }

        let modal = UIView(frame: parent.bounds)
        modal.accessibilityViewIsModal = true
        modal.isAccessibilityElement = false

        let label = UILabel(frame: CGRect(x: 20, y: 60, width: 220, height: 44))
        label.text = "Modal Boundary"
        label.isAccessibilityElement = true
        modal.addSubview(label)

        parent.addSubview(modal)
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
