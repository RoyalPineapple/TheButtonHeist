#if canImport(UIKit)
import UIKit
import XCTest

@testable import BHDemo
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class LiveTargetReuseIntegrationTests: XCTestCase {

    func testRetainedTargetNeverDispatchesAfterObjectRepresentsDifferentSemanticItem() async throws {
        let fixture = try makeDemoCollectionFixture()
        defer { fixture.remove() }

        let stash = TheStash(tripwire: TheTripwire())
        _ = try XCTUnwrap(stash.refreshLiveCapture())
        let retained = try XCTUnwrap(fixture.collectionView.visibleCells.lazy.compactMap { cell in
            self.retainedTarget(for: cell, in: stash)
        }.first)

        retained.object.accessibilityLabel = "Reused Semantic Item"
        _ = try XCTUnwrap(stash.refreshLiveCapture())
        let reusedObjectCurrentHeistID = try XCTUnwrap(stash.liveElementHeistId(matching: retained.object))
        XCTAssertNotEqual(reusedObjectCurrentHeistID, retained.heistID)

        var invokedObjectID: ObjectIdentifier?
        let dispatch = stash.dispatchOnFreshLiveActionTarget(retained.target) { current in
            invokedObjectID = ObjectIdentifier(current.object)
            return current.treeElement.heistId
        }

        switch dispatch {
        case .success(let heistID):
            XCTAssertEqual(heistID, retained.heistID)
            XCTAssertNotEqual(invokedObjectID, ObjectIdentifier(retained.object))
        case .failure:
            XCTAssertNil(invokedObjectID)
        }
    }

    private func retainedTarget(
        for cell: UICollectionViewCell,
        in stash: TheStash
    ) -> RetainedTarget? {
        guard let heistID = stash.liveElementHeistId(matching: cell),
              let treeElement = stash.latestObservation.tree.findElement(heistId: heistID),
              case .resolved(let target) = stash.resolveLiveActionTarget(for: treeElement)
        else { return nil }
        return RetainedTarget(
            heistID: heistID,
            object: cell,
            target: target
        )
    }

    private func makeDemoCollectionFixture() throws -> DemoCollectionFixture {
        let windowScene = try requireForegroundWindowScene()
        let rootViewController = UIViewController()
        rootViewController.view.backgroundColor = .white
        rootViewController.view.accessibilityViewIsModal = true

        let demo = DemoCollectionViewController()
        rootViewController.addChild(demo)
        rootViewController.view.addSubview(demo.view)
        demo.view.frame = CGRect(x: 0, y: 80, width: windowScene.screen.bounds.width, height: 150)
        demo.didMove(toParent: rootViewController)

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.screen.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = rootViewController
        window.isHidden = false
        window.layoutIfNeeded()
        demo.collectionView.layoutIfNeeded()

        return DemoCollectionFixture(
            window: window,
            rootViewController: rootViewController,
            collectionView: demo.collectionView
        )
    }
}

private struct RetainedTarget {
    let heistID: HeistId
    let object: UICollectionViewCell
    let target: TheStash.LiveActionTarget
}

private struct DemoCollectionFixture {
    let window: UIWindow
    let rootViewController: UIViewController
    let collectionView: UICollectionView

    @MainActor func remove() {
        rootViewController.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

#endif // canImport(UIKit)
