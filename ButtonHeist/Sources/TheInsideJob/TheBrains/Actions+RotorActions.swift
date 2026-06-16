#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    // MARK: - Rotor Actions

    func executeRotor(
        _ target: RotorTarget
    ) async -> TheSafecracker.InteractionResult {
        let direction = target.direction
        let rotor = target.selection.rotorName
        let rotorIndex = target.selection.rotorIndex
        let method: ActionMethod = .rotor
        return await performElementAction(
            target: target.elementTarget,
            method: method,
            requireInteractive: false,
            activationPointPolicy: .liveObjectOnly
        ) { context in
            let outcome = self.stash.performRotor(
                selection: target.selection,
                direction: direction,
                on: context.liveTarget
            )
            if case .succeeded(let hit) = outcome {
                await self.exposeRotorResultIfPossible(hit)
            }
            return Self.rotorInteractionResult(
                outcome: outcome,
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                liveTarget: context.liveTarget
            )
        }
    }

    private func exposeRotorResultIfPossible(_ hit: TheStash.RotorHit) async {
        guard let screenElement = hit.screenElement else { return }

        if case .objectUnavailable = stash.resolveLiveActionTarget(for: screenElement) {
            let reveal = navigation.elementInflation.revealSemanticTarget(screenElement)
            if reveal.didReveal {
                await tripwire.yieldFrames(ElementInflation.postScrollLayoutFrames)
                stash.refreshLiveCapture()
            }
        }

        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: screenElement) else {
            return
        }

        let description = Navigation.ScrollTargetDescription(liveTarget.screenElement).description
        _ = await navigation.elementInflation.scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: liveTarget.screenElement),
            method: .rotor,
            noScrollViewFailure: .geometryNotActionable(
                "rotor result \(description) has no live scrollable ancestor to make activation point actionable"
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: "rotor result \(description) activation point could not be brought on-screen"
        )
    }

    // MARK: - Diagnostic Helpers

    private static func rotorInteractionResult(
        outcome: TheStash.RotorOutcome,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        liveTarget: TheStash.LiveActionTarget
    ) -> TheSafecracker.InteractionResult {
        let element = liveTarget.screenElement
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
            return rotorFailure(observed: "requestedRotor=\(ActionCapabilityDiagnostic.quote(rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use one of available rotors \(ActionCapabilityDiagnostic.formatQuotedList(available))")
        case .ambiguousRotor(let available):
            return rotorFailure(observed: "ambiguousRotor=\(ActionCapabilityDiagnostic.quote(rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "specify rotorIndex or an exact rotor name")
        case .currentItemUnavailable(let heistId):
            return rotorFailure(
                observed: "rotor continuation target \(ActionCapabilityDiagnostic.quote(heistId)) is not available",
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
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned no \(direction.rawValue) result",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "try the opposite rotor direction or stop at the current item"
            )
        case .resultTargetUnavailable(let rotorName):
            return rotorFailure(
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a result without an accessibility target",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "retry the rotor from a semantic target that can be made actionable"
            )
        case .resultTargetNotParsed(let rotorName):
            return rotorFailure(
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a target outside the parsed hierarchy",
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
    ) -> TheSafecracker.InteractionResult {
        let foundElement = hit.screenElement.map { HeistElement(accessibilityElement: $0.element) }
        var message = "Rotor '\(hit.rotor)' found"
        if let describedElement = foundElement?.label ?? foundElement?.description {
            message += " \(describedElement)"
        }
        if let textRange = hit.textRange {
            message += " text range \(textRange.rangeDescription)"
        }
        return .success(
            method: .rotor,
            message: message,
            payload: .rotor(RotorResult(
                rotor: hit.rotor,
                direction: direction,
                foundElement: foundElement,
                textRange: hit.textRange
            ))
        )
    }

    private static func rotorFailure(
        observed: String,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        element: TheStash.ScreenElement,
        liveObject: NSObject,
        suggestion: String,
        failureKind: TheSafecracker.FailureKind? = nil
    ) -> TheSafecracker.InteractionResult {
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
        element: TheStash.ScreenElement,
        liveObject: NSObject,
        suggestion: String
    ) -> String {
        var attempted: [String] = []
        if let rotor {
            attempted.append("rotor=\(ActionCapabilityDiagnostic.quote(rotor))")
        } else {
            attempted.append("rotor")
        }
        if let rotorIndex {
            attempted.append("rotorIndex=\(rotorIndex)")
        }
        attempted.append("direction=\(direction.rawValue)")

        let availableRotors = ActionCapabilityDiagnostic.availableRotors(for: element, liveObject: liveObject)
        return "rotor failed: attempted \(attempted.joined(separator: " ")) "
            + "on \(ActionCapabilityDiagnostic.formatElement(element, liveObject: liveObject)) "
            + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(availableRotors)); "
            + "observed \(observed); try \(suggestion)."
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
