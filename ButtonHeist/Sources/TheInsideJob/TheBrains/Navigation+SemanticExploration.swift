#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    struct ContainerPage {
        let elements: [AccessibilityElement]
        let origins: [CGPoint?]
    }

    struct ContainerScan {
        var accumulated: [AccessibilityElement]
        var accumulatedOrigins: [CGPoint?]
        var originByElement: [AccessibilityElement: CGPoint?]
    }

    struct ContainerExploration {
        let container: AccessibilityContainer
        let scrollTarget: ScrollableTarget
        let hasHOverflow: Bool
        let hasVOverflow: Bool
        let ancestorRestorations: [ViewportRestoration]

        var direction: UIAccessibilityScrollDirection { hasHOverflow ? .right : .down }

        var leadingEdge: ScrollEdge { hasHOverflow ? .left : .top }

        @MainActor
        var savedVisualOrigin: CGPoint? {
            guard case .uiScrollView(let scrollView) = scrollTarget else { return nil }
            return CGPoint(
                x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
                y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            )
        }
    }

    struct ViewportRestoration {
        let scrollView: UIScrollView
        let visualOrigin: CGPoint
    }

    struct ExploredScreen {
        let screen: Screen
        let manifest: ScreenManifest
    }

    struct SemanticExploration {
        var screen: Screen
        var manifest: ScreenManifest

        init(
            baseline: Screen,
            maxScrollsPerContainer: Int = ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = ScreenManifest.maxScrollsPerDiscovery
        ) {
            screen = baseline
            manifest = ScreenManifest(
                maxScrollsPerContainer: maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery
            )
        }

        mutating func absorb(_ parsed: Screen?) {
            guard let parsed else { return }
            screen = screen.merging(parsed)
            addDiscoveredContainers(parsed.liveCapture.hierarchy.scrollableContainers)
        }

        mutating func markExplored(_ container: AccessibilityContainer) {
            manifest.markExplored(container)
        }

        mutating func addDiscoveredContainers(_ containers: [AccessibilityContainer]) {
            let newContainers = containers.filter {
                !manifest.exploredContainers.contains($0)
                    && !manifest.pendingContainers.contains($0)
            }
            manifest.addPendingContainers(newContainers)
        }

        mutating func finish(startTime: CFTimeInterval) -> ExploredScreen {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return ExploredScreen(screen: screen, manifest: manifest)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
