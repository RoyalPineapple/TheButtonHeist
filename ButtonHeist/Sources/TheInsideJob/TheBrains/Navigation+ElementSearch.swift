#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore

// MARK: - Element Search

extension Navigation {

    /// Iterative search: page through scroll content looking for an element.
    /// `element_search` never delegates to semantic reveal/actionability commands.
    func executeElementSearch(
        elementTarget: ElementTarget?,
        direction: ScrollDirection
    ) async -> TheSafecracker.InteractionResult {
        guard let searchTarget = elementTarget else {
            return .failure(.elementSearch, message: "Element target required for element_search")
        }
        let searchDirection = direction
        let requestedAxis = Self.requiredAxis(for: searchDirection)

        var candidates = scrollSearchCandidates(requiredAxis: requestedAxis)
        if let seed = scrollSearchSeedCandidate(for: searchTarget, requiredAxis: requestedAxis),
           !candidates.contains(where: { $0.container == seed.container }) {
            candidates.insert(seed, at: 0)
        }
        var progress = ScrollSearchProgress(
            initialVisibleHeistIds: stash.visibleIds,
            knownContainers: Set(candidates.map(\.container)),
            maxScrolls: Self.scrollSearchMaxScrolls
        )

        if let found = stash.resolveFirstVisibleMatch(searchTarget) {
            return searchFoundResult(
                found, scrollCount: 0,
                uniqueElementsSeen: progress.uniqueElementsSeen
            )
        }

        while progress.canScrollMore {
            refreshScrollSearchCandidates(
                requiredAxis: requestedAxis,
                candidates: &candidates,
                progress: &progress
            )

            guard let plan = candidates.first(where: {
                !progress.exhaustedContainers.contains($0.container)
            }) else { break }

            progress.markContainerSearched(plan.container)
            let proof = await scrollOnePageAndSettle(
                plan.target,
                direction: Self.uiScrollDirection(for: searchDirection)
            )

            if proof.result == .unchanged {
                progress.markContainerExhausted(plan.container)
                continue
            }

            progress.markScrolledPage(in: plan.container, visibleHeistIds: stash.visibleIds)
            refreshScrollSearchCandidates(
                requiredAxis: requestedAxis,
                candidates: &candidates,
                progress: &progress
            )
            if let found = stash.resolveFirstVisibleMatch(searchTarget) {
                return searchFoundResult(
                    found, scrollCount: progress.scrollCount,
                    uniqueElementsSeen: progress.uniqueElementsSeen
                )
            }

            if stash.visibleIds == proof.previousVisibleIds {
                progress.markContainerExhausted(plan.container)
            }
        }

        return searchNotFoundResult(progress: progress)
    }

    private func refreshScrollSearchCandidates(
        requiredAxis axis: ScrollAxis?,
        candidates: inout [ScrollPlan],
        progress: inout ScrollSearchProgress
    ) {
        candidates = scrollSearchCandidates(requiredAxis: axis).reduce(into: candidates) { merged, candidate in
            if let index = merged.firstIndex(where: { $0.container == candidate.container }) {
                merged[index] = candidate
            } else {
                merged.append(candidate)
            }
        }
        progress.recordKnownContainers(candidates.map(\.container))
    }

    private func searchNotFoundResult(progress: ScrollSearchProgress) -> TheSafecracker.InteractionResult {
        .failure(
            .elementSearch,
            message: searchNotFoundMessage(progress: progress),
            payload: .scrollSearch(ScrollSearchResult(
                scrollCount: progress.scrollCount,
                uniqueElementsSeen: progress.uniqueElementsSeen,
                exhaustive: progress.exhaustive
            ))
        )
    }

    private func searchFoundResult(
        _ found: TheStash.ScreenElement,
        scrollCount: Int,
        uniqueElementsSeen: Int
    ) -> TheSafecracker.InteractionResult {
        return .success(
            method: .elementSearch,
            payload: .scrollSearch(ScrollSearchResult(
                scrollCount: scrollCount,
                uniqueElementsSeen: uniqueElementsSeen,
                exhaustive: false,
                found: true
            ))
        )
    }

    private func searchNotFoundMessage(progress: ScrollSearchProgress) -> String {
        let containerLabel = progress.containersSearched == 1 ? "container" : "containers"
        let pageLabel = progress.pagesSearched == 1 ? "page" : "pages"
        let capSuffix = progress.didHitScrollCap
            ? " (capped at \(progress.maxScrolls) scrolls)"
            : ""
        return "Element not found after \(progress.scrollCount) scrolls across "
            + "\(progress.pagesSearched) \(pageLabel) in "
            + "\(progress.containersSearched) \(containerLabel)\(capSuffix)"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
