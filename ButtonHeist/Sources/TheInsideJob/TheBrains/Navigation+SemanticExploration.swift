#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    struct ContainerPage {
        let entries: [ContainerPageEntry]

        var elements: [AccessibilityElement] {
            entries.map(\.element)
        }

        var origins: [CGPoint?] {
            entries.map(\.origin)
        }
    }

    struct ContainerPageEntry: Equatable {
        let path: TreePath
        let heistId: HeistId
        let element: AccessibilityElement
        let origin: CGPoint?
    }

    struct ContainerScan {
        var accumulated: [ContainerPageEntry]
    }

    struct ContainerPageReconciliation: Equatable {
        let entries: [ContainerPageEntry]
        let overlap: OverlapResult
        let inserted: [ContainerPageEntry]
        let previousCount: Int
    }

    enum ContainerScanResult: Equatable {
        case foundTarget
        case completed
        case omitted(ExplorationOmissionReason)
    }

    struct ContainerExploration {
        let semanticContainer: SemanticScreen.Container
        let scrollTarget: ScrollableTarget
        let hasHOverflow: Bool
        let hasVOverflow: Bool
        let ancestorRestorations: [ViewportRestoration]

        var container: AccessibilityContainer { semanticContainer.container }

        var path: TreePath { semanticContainer.path }

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
            addDiscoveredContainers(parsed.orderedContainers.filter { $0.container.isScrollable })
        }

        mutating func markExplored(_ container: SemanticScreen.Container) {
            manifest.markExplored(container.path)
        }

        mutating func addDiscoveredContainers(_ containers: [SemanticScreen.Container]) {
            let newContainers = containers.filter {
                !manifest.exploredContainerPaths.contains($0.path)
                    && !manifest.pendingContainerPaths.contains($0.path)
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
