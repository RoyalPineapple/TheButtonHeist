#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    // MARK: - Rotor Actions

    private static let rotorStringProfile = ElementDiagnosticSummary.RenderProfile.actionCapability

    func executeRotor(
        selection: RotorSelection,
        target: ResolvedAccessibilityTarget,
        direction: RotorDirection
    ) async -> TheSafecracker.ActionDispatchOutcome {
        let rotor = selection.rotorName
        let rotorIndex = selection.rotorIndex
        let method: ActionMethod = .rotor
        return await performElementAction(
            target: target,
            method: method,
            requireInteractive: false,
            activationPointPolicy: .liveObjectOnly
        ) { context in
            let outcome = self.stash.performRotor(
                selection: selection,
                direction: direction,
                on: context.liveTarget
            )
            if case .succeeded(let hit) = outcome {
                await self.exposeRotorResultIfPossible(hit)
            }
            return Self.rotorDispatchOutcome(
                outcome: outcome,
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                liveTarget: context.liveTarget
            )
        }
    }

    private func exposeRotorResultIfPossible(_ hit: TheStash.RotorHit) async {
        guard let treeElement = hit.treeElement else { return }

        if case .objectUnavailable = stash.resolveLiveActionTarget(for: treeElement) {
            _ = await navigation.elementInflation.revealSemanticTarget(
                treeElement,
                deadline: navigation.elementInflation.handoffDeadline(for: treeElement)
            )
        }

        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: treeElement) else {
            return
        }

        let description = Navigation.ScrollTargetDescription(liveTarget.treeElement).description
        _ = await navigation.elementInflation.scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: liveTarget.treeElement),
            method: .rotor,
            noScrollViewFailure: .geometryNotActionable(
                "rotor result \(description) has no live scrollable ancestor to make activation point actionable"
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: "rotor result \(description) activation point could not be brought on-screen"
        )
    }

    // MARK: - Diagnostic Helpers

    private static func rotorDispatchOutcome(
        outcome: TheStash.RotorOutcome,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        liveTarget: TheStash.LiveActionTarget
    ) -> TheSafecracker.ActionDispatchOutcome {
        let element = liveTarget.treeElement
        let liveObject = liveTarget.object
        switch outcome {
        case .succeeded(let hit):
            return rotorSuccessResult(hit, direction: direction)
        case .deallocated:
            return rotorFailure(
                observed: "liveObject=deallocated before rotor step",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "retry the same semantic target after UI settles",
                failureKind: .targetUnavailable
            )
        case .noRotors:
            return rotorFailure(observed: "customRotors=[]",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "target an element exposing custom rotors")
        case .noSuchRotor(let available):
            return rotorFailure(observed: "requestedRotor=\(rotorStringProfile.renderString(rotor ?? "")) "
                                + "availableRotors=\(rotorStringProfile.renderList(available, itemStyle: .quoted))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use one of available rotors \(rotorStringProfile.renderList(available, itemStyle: .quoted))")
        case .ambiguousRotor(let available):
            return rotorFailure(observed: "ambiguousRotor=\(rotorStringProfile.renderString(rotor ?? "")) "
                                + "availableRotors=\(rotorStringProfile.renderList(available, itemStyle: .quoted))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "specify rotorIndex or an exact rotor name")
        case .currentItemUnavailable(let heistId):
            return rotorFailure(
                observed: "rotor continuation target \(rotorStringProfile.renderString(heistId)) is not available",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "start from the semantic target again or use the current continuation returned by the previous rotor result",
                failureKind: .targetUnavailable
            )
        case .continuationTextRangeUnavailable:
            return rotorFailure(observed: "continuation.textRange is not available",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use the text range returned by the previous rotor result")
        case .noResult(let rotorName):
            return rotorFailure(
                observed: "rotor=\(rotorStringProfile.renderString(rotorName)) returned no \(direction.rawValue) result",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "try the opposite rotor direction or stop at the current item"
            )
        case .resultTargetUnavailable(let rotorName):
            return rotorFailure(
                observed: "rotor=\(rotorStringProfile.renderString(rotorName)) returned a result without an accessibility target",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "retry the rotor from a semantic target that can be made actionable"
            )
        case .resultTargetNotParsed(let rotorName):
            return rotorFailure(
                observed: "rotor=\(rotorStringProfile.renderString(rotorName)) returned a target outside the parsed hierarchy",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "rerun the rotor and act on the returned semantic target after it is parsed"
            )
        }
    }

    private static func rotorSuccessResult(
        _ hit: TheStash.RotorHit,
        direction: RotorDirection
    ) -> TheSafecracker.ActionDispatchOutcome {
        let foundElement = hit.treeElement.map { HeistElement(accessibilityElement: $0.element) }
        var message = "Rotor '\(hit.rotor)' found"
        if let describedElement = foundElement?.label ?? foundElement?.description {
            message += " \(describedElement)"
        }
        if let textRange = hit.textRange {
            message += " text range \(textRange.rangeDescription)"
        }
        return .success(
            payload: .rotor(RotorResult(
                rotor: hit.rotor,
                direction: direction,
                foundElement: foundElement,
                textRange: hit.textRange
            )),
            message: message
        )
    }

    private static func rotorFailure(
        observed: String,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        element: InterfaceTree.Element,
        liveObject: NSObject,
        suggestion: String,
        failureKind: TheSafecracker.FailureKind = .actionFailed
    ) -> TheSafecracker.ActionDispatchOutcome {
        .failure(
            .rotor,
            message: rotorDiagnostic(
                observed: observed,
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: suggestion
            ),
            failureKind: failureKind
        )
    }

    private static func rotorDiagnostic(
        observed: String,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        element: InterfaceTree.Element,
        liveObject: NSObject,
        suggestion: String
    ) -> String {
        var attempted: [String] = []
        if let rotor {
            attempted.append("rotor=\(rotorStringProfile.renderString(rotor))")
        } else {
            attempted.append("rotor")
        }
        if let rotorIndex {
            attempted.append("rotorIndex=\(rotorIndex)")
        }
        attempted.append("direction=\(direction.rawValue)")

        let availableRotors = ActionCapabilityDiagnostic.availableRotors(for: element, liveObject: liveObject)
        return "rotor failed: attempted \(attempted.joined(separator: " ")) "
            + "on \(ActionCapabilityDiagnostic.elementObservation(element, liveObject: liveObject)) "
            + "availableRotors=\(rotorStringProfile.renderList(availableRotors, itemStyle: .quoted)); "
            + "observed \(observed); try \(suggestion)."
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
