#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    struct ContainerExploration {
        let semanticContainer: SemanticScreen.Container
        let scrollView: UIScrollView
        let hasHOverflow: Bool
        let hasVOverflow: Bool

        var container: AccessibilityContainer { semanticContainer.container }

        var path: TreePath { semanticContainer.path }

        @MainActor
        var savedVisualOrigin: CGPoint {
            Navigation.visualOrigin(in: scrollView)
        }
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
