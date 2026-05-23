#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    // MARK: - Rotor Actions

    func executeRotor(
        _ target: some RotorExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let direction = target.direction ?? .next
        let method: ActionMethod = .rotor
        return await performElementAction(
            target: target.rotorElementTarget,
            method: method,
            recordedScreen: recordedScreen,
            requireInteractive: false
        ) { context in
            let outcome = self.stash.performRotor(
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                currentHeistId: target.currentHeistId,
                currentTextRange: target.currentTextRange,
                direction: direction,
                on: context.liveTarget
            )
            return Self.rotorInteractionResult(
                outcome: outcome,
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                direction: direction,
                liveTarget: context.liveTarget
            )
        }
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
                .elementDeallocated,
                observed: "liveObject=deallocated before rotor step",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "refresh with get_interface and retarget the refreshed element"
            )
        case .noRotors:
            return rotorFailure(.rotor, observed: "customRotors=[]",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "target an element exposing custom rotors")
        case .noSuchRotor(let available):
            return rotorFailure(.rotor, observed: "requestedRotor=\(ActionCapabilityDiagnostic.quote(rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use one of available rotors \(ActionCapabilityDiagnostic.formatQuotedList(available))")
        case .ambiguousRotor(let available):
            return rotorFailure(.rotor, observed: "ambiguousRotor=\(ActionCapabilityDiagnostic.quote(rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "specify rotorIndex or an exact rotor name")
        case .currentItemUnavailable(let heistId):
            return rotorFailure(
                .elementNotFound,
                observed: "currentHeistId=\(ActionCapabilityDiagnostic.quote(heistId)) is not available",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "use the heistId returned by the previous rotor result after refetching"
            )
        case .currentTextRangeUnavailable:
            return rotorFailure(.rotor, observed: "currentTextRange is not available",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use the text range returned by the previous rotor result after refetching")
        case .noResult(let rotorName):
            return rotorFailure(
                .rotor,
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
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a result without an accessibility target",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "refetch with get_interface and retry the rotor from a visible target"
            )
        case .resultTargetNotParsed(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a target outside the parsed hierarchy",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "refetch with get_interface before acting on the rotor result"
            )
        }
    }

    private static func rotorSuccessResult(
        _ hit: TheStash.RotorHit,
        direction: RotorDirection
    ) -> TheSafecracker.InteractionResult {
        let found = hit.screenElement.map(TheStash.WireConversion.toWire)
        var message = "Rotor '\(hit.rotor)' found"
        if let found {
            message += " \(found.heistId)"
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
                foundElement: found,
                textRange: hit.textRange
            ))
        )
    }

    private static func rotorFailure(
        _ method: ActionMethod,
        observed: String,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        element: TheStash.ScreenElement,
        liveObject: NSObject,
        suggestion: String
    ) -> TheSafecracker.InteractionResult {
        .failure(
            method,
            message: rotorDiagnostic(
                observed: observed,
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: suggestion
            )
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
