#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class TheVaultCaptureTests: XCTestCase {

    private var vault: TheVault!

    override func setUp() async throws {
        try await super.setUp()
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault = nil
        try await super.tearDown()
    }

    func testCaptureReturnsNilWhenNoAccessibleWindows() throws {
        let result = withNoTraversableWindows {
            vault.refreshLiveCapture()
        }
        XCTAssertNil(result)
    }

    func testInjectedObservationSourceRemainsTheRefreshOwnerAcrossLifecycleReset() async {
        let observation = InterfaceObservation.empty
        var captureCount = 0
        let injectedVault = TheVault(
            tripwire: TheTripwire(),
            visibleObservationSource: { _ in
                captureCount += 1
                return observation
            }
        )

        XCTAssertEqual(injectedVault.refreshLiveCapture()?.captureID, observation.captureID)
        await injectedVault.resetInterfaceForLifecycle()
        XCTAssertEqual(injectedVault.refreshLiveCapture()?.captureID, observation.captureID)
        XCTAssertEqual(captureCount, 2)
    }

    func testCaptureDoesNotMutateSearchBarHiding() throws {
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
        XCTAssertNotNil(vault.refreshLiveCapture())
        XCTAssertTrue(
            contentVC.navigationItem.hidesSearchBarWhenScrolling,
            "refreshLiveCapture() should not change hidesSearchBarWhenScrolling"
        )
    }

    func testCaptureWrapsEachWindowWithSemanticGroupInMultiWindowMode() throws {
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

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for multi-window scene")
            return
        }

        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(levelA.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(levelB.rawValue)"))
    }

    func testCaptureIncludesBaseWindowWhenElevatedNonModalWindowIsPresent() throws {
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

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture with base and elevated non-modal windows")
            return
        }

        let labels = result.liveCapture.hierarchy.sortedElements.compactMap(\.label)
        XCTAssertTrue(
            labels.contains("Window \(Int(UIWindow.Level.normal.rawValue))"),
            "Elevated non-modal windows should not hide the base app window"
        )
        XCTAssertTrue(
            labels.contains("Reader Overlay"),
            "Elevated non-modal windows should contribute their own accessible content"
        )
    }

    func testCaptureIncludesAllAppWindowsWhenNoModalBoundaryAppears() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let overlay = makeWindow(windowScene: windowScene, level: .alert)
            let appWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)
            let lower = makeWindow(windowScene: windowScene, level: .normal - 1)

            defer {
                overlay.isHidden = true
                appWindow.isHidden = true
                lower.isHidden = true
            }

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for all app windows")
            return
        }

        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.alert.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \((UIWindow.Level.normal - 1).rawValue)"))
    }

    func testCaptureStopsBelowModalBoundaryAboveAppWindow() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let modalOverlay = makeWindow(windowScene: windowScene, level: .alert)
            addModalBoundary(to: modalOverlay)

            let keyWindow = makeWindow(windowScene: windowScene, level: .normal, makeKey: true)

            defer {
                modalOverlay.isHidden = true
                keyWindow.isHidden = true
            }

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for modal overlay")
            return
        }

        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.alert.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testCaptureKeepsWindowsAboveLowerModalBoundary() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = withNoTraversableWindows {
            let lowerModal = makeWindow(windowScene: windowScene, level: .normal)
            addModalBoundary(to: lowerModal)
            let keyWindow = makeWindow(windowScene: windowScene, level: .alert, makeKey: true)

            defer {
                keyWindow.isHidden = true
                lowerModal.isHidden = true
            }

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for upper window and lower modal")
            return
        }

        let labels = result.liveCapture.hierarchy.sortedElements.compactMap(\.label)
        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(labels.contains("Window \(Int(UIWindow.Level.alert.rawValue))"))
        XCTAssertTrue(labels.contains("Modal Boundary"))
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testCaptureStopsAtFrontmostModalBoundary() throws {
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

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for stacked modal windows")
            return
        }

        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: 2000.0"))
        XCTAssertFalse(values.contains("windowLevel: 100.0"))
        XCTAssertFalse(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testCaptureKeepsOverlaysAboveModalBoundaryAndDropsLowerWindows() throws {
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

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for overlay and modal windows")
            return
        }

        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: 2000.0"))
        XCTAssertTrue(values.contains("windowLevel: 1999.0"))
        XCTAssertTrue(values.contains("windowLevel: \(modalLevel.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
    }

    func testCaptureTreatsDeepModalSubviewAsWindowBoundary() throws {
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

            return vault.refreshLiveCapture()
        }

        guard let result else {
            XCTFail("Expected capture for deep modal boundary")
            return
        }

        let values = semanticGroupValues(in: result.liveCapture.hierarchy)
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.alert.rawValue)"))
        XCTAssertTrue(values.contains("windowLevel: \(UIWindow.Level.normal.rawValue)"))
        XCTAssertFalse(values.contains("windowLevel: \((UIWindow.Level.normal - 1).rawValue)"))
    }

    func testCaptureIncludesPopoverContentSiblingAfterDismissRegion() throws {
        let windowScene = try requireForegroundWindowScene()

        let result = try withNoTraversableWindows {
            let viewController = UIViewController()
            viewController.view.frame = UIScreen.main.bounds
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
            window.layoutIfNeeded()

            defer {
                window.isHidden = true
            }

            let capture = try XCTUnwrap(
                vault.capture(),
                "Expected capture for popover-style modal window"
            )
            return try TheVault.admitObservation(from: capture)
        }

        let labels = result.liveCapture.hierarchy.sortedElements.compactMap(\.label)
        XCTAssertTrue(
            labels.contains("Popover Action"),
            "Popover content presented as a sibling after the dismiss region should be parsed"
        )
        XCTAssertFalse(
            labels.contains("Background Should Not Appear"),
            "Background siblings before the modal dismiss region should remain excluded"
        )
    }

    // MARK: - Inventory request admission

    func testInventoryEnumerationWithZeroBudgetAndEmptyInventoryRequestsNothing() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 0)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 0
        )

        XCTAssertEqual(scrollView.requestedIndices, [])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.reportedCountsByContainerPath[path], .known(0))
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], nil)
        XCTAssertEqual(result.knownUnattemptedCount, 0)
    }

    func testInventoryEnumerationWithZeroBudgetAndNonemptyInventoryRequestsNothing() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 4)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 0
        )

        XCTAssertEqual(scrollView.requestedIndices, [])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], nil)
        XCTAssertEqual(result.knownUnattemptedCount, 4)
    }

    func testInventoryEnumerationBelowBudgetRequestsEveryReportedIndex() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 2)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 3
        )

        XCTAssertEqual(scrollView.requestedIndices, [0, 1])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], [0, 1])
        XCTAssertEqual(result.knownUnattemptedCount, 0)
    }

    func testInventoryEnumerationAtBudgetRequestsEveryReportedIndex() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 3)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 3
        )

        XCTAssertEqual(scrollView.requestedIndices, [0, 1, 2])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], [0, 1, 2])
        XCTAssertEqual(result.knownUnattemptedCount, 0)
    }

    func testInventoryEnumerationAboveBudgetStopsBeforeNextRequest() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 4)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 3
        )

        XCTAssertEqual(scrollView.requestedIndices, [0, 1, 2])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], [0, 1, 2])
        XCTAssertEqual(result.knownUnattemptedCount, 1)
    }

    func testInventoryEnumerationConsumesBudgetForEveryUnsuccessfulAttempt() {
        struct UnsupportedInventoryValue {}

        let path = TreePath([0])
        let representedObject = UILabel()
        let scrollView = RecordingInventoryScrollView(
            reportedCount: 5,
            elementAtIndex: { index in
                switch index {
                case 0: representedObject
                case 1: nil
                case 2: UnsupportedInventoryValue()
                case 3: NSObject()
                default: UIAccessibilityElement(accessibilityContainer: NSObject())
                }
            }
        )

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [TreePath([9]): representedObject],
            scrollViewsByPath: [path: scrollView],
            budget: 4
        )

        XCTAssertEqual(scrollView.requestedIndices, [0, 1, 2, 3])
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], [0, 1, 2, 3])
        XCTAssertEqual(result.knownUnattemptedCount, 1)
    }

    func testInventoryEnumerationSharesOneBudgetAcrossContainersInPathOrder() {
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        let first = RecordingInventoryScrollView(reportedCount: 2)
        let second = RecordingInventoryScrollView(reportedCount: 2)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [secondPath: second, firstPath: first],
            budget: 3
        )

        XCTAssertEqual(first.requestedIndices, [0, 1])
        XCTAssertEqual(second.requestedIndices, [0])
        XCTAssertEqual(first.countRequestCount, 1)
        XCTAssertEqual(second.countRequestCount, 1)
        XCTAssertEqual(result.attemptedIndicesByContainerPath[firstPath], [0, 1])
        XCTAssertEqual(result.attemptedIndicesByContainerPath[secondPath], [0])
        XCTAssertEqual(result.knownUnattemptedCount, 1)
    }

    func testInventoryEnumerationFarAboveBudgetDoesNotScaleElementRequestsWithReportedCount() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 1_000_000)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 2
        )

        XCTAssertEqual(scrollView.requestedIndices, [0, 1])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.attemptedIndicesByContainerPath[path], [0, 1])
        XCTAssertEqual(result.knownUnattemptedCount, 999_998)
    }

    func testInventoryEnumerationPreservesUnknownCountWithoutElementRequests() {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: NSNotFound)

        let result = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 3
        )

        XCTAssertEqual(scrollView.requestedIndices, [])
        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(result.reportedCountsByContainerPath[path], .unknown)
        XCTAssertEqual(result.knownUnattemptedCount, 0)
    }

    func testBuildFactsReusesInventoryEnumerationCountSnapshot() throws {
        let path = TreePath([0])
        let scrollView = RecordingInventoryScrollView(reportedCount: 2)
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let enumeration = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [path: scrollView],
            budget: 0
        )
        let capture = TheVault.CaptureResult(
            hierarchy: [.container(makeScrollableContainer(), children: [])],
            containerObjectsByPath: [path: scrollView],
            scrollViewsByPath: [path: scrollView],
            inventoryEnumeration: enumeration
        )

        let observation = TheVault.buildObservation(from: capture)

        XCTAssertEqual(scrollView.countRequestCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(observation.tree.containers[path]?.scrollInventory).totalElementCount,
            2
        )
    }

    private func makeScrollableContainer() -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_600),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 400)
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
                if case let .semanticGroup(_, value) = container.type, let value {
                    values.append(value)
                }
                values.append(contentsOf: semanticGroupValues(in: children))
            }
        }
        return values
    }

    private func withNoTraversableWindows<T>(
        _ operation: () throws -> T
    ) rethrows -> T {
        let windows = vault.tripwire.captureTraversableWindows().map(\.window)
        let originalHiddenStates = windows.map(\.isHidden)
        for window in windows {
            window.isHidden = true
        }
        defer {
            for (window, originalIsHidden) in zip(windows, originalHiddenStates) {
                window.isHidden = originalIsHidden
            }
        }
        return try operation()
    }

}

@MainActor
private final class RecordingInventoryScrollView: UIScrollView {
    private let reportedCount: Int
    private let elementAtIndex: (Int) -> Any?
    private(set) var countRequestCount = 0
    private(set) var requestedIndices: [Int] = []

    init(
        reportedCount: Int,
        elementAtIndex: @escaping (Int) -> Any? = { _ in nil }
    ) {
        self.reportedCount = reportedCount
        self.elementAtIndex = elementAtIndex
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func accessibilityElementCount() -> Int {
        countRequestCount += 1
        return reportedCount
    }

    override func accessibilityElement(at index: Int) -> Any? {
        requestedIndices.append(index)
        return elementAtIndex(index)
    }
}

#endif
