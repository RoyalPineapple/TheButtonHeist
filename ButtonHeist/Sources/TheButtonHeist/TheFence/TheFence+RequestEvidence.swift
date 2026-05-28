import Foundation

import TheScore

private let evidenceTargetKeys: Set<String> = [
    "heistId", "label", "identifier", "value", "traits", "excludeTraits",
    "ordinal", "elementTarget",
]

extension HeistValue {
    static func encoded<T: Encodable>(_ value: T) -> HeistValue {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(HeistValue.self, from: data)
        } catch {
            return .object([
                "type": .string("encoding_failed"),
                "error": .string(String(describing: error)),
            ])
        }
    }
}

private extension Encodable {
    func heistEvidenceArguments(renaming renamedKeys: [String: String] = [:]) -> [String: HeistValue] {
        guard case .object(let encoded) = HeistValue.encoded(self) else { return [:] }
        var arguments = encoded.reduce(into: [String: HeistValue]()) { result, pair in
            guard !evidenceTargetKeys.contains(pair.key) else { return }
            result[renamedKeys[pair.key] ?? pair.key] = pair.value
        }
        arguments.flattenRotorTextRange()
        return arguments
    }
}

private extension Dictionary where Key == String, Value == HeistValue {
    mutating func flattenRotorTextRange() {
        guard case .object(let textRange)? = removeValue(forKey: "currentTextRange") else { return }
        if let startOffset = textRange["startOffset"] {
            self["currentTextStartOffset"] = startOffset
        }
        if let endOffset = textRange["endOffset"] {
            self["currentTextEndOffset"] = endOffset
        }
    }
}

struct ActivateEvidenceArguments: Encodable {
    let action: String?
    let count: Int?
}

extension TheFence.RequestEvidence {
    static func target(
        arguments: [String: HeistValue],
        elementTarget: ElementTarget?
    ) -> Self {
        Self(arguments: arguments, elementTarget: elementTarget)
    }
}

extension Encodable {
    func heistEvidenceArguments() -> [String: HeistValue] {
        heistEvidenceArguments(renaming: [:])
    }
}

extension TapTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"]),
            elementTarget: selection.elementTarget,
            coordinateOnly: selection.screenPoint != nil
        )
    }
}

extension LongPressTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"]),
            elementTarget: selection.elementTarget,
            coordinateOnly: selection.screenPoint != nil
        )
    }
}

extension SwipeTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: selection.bookKeeperElementTarget,
            coordinateOnly: selection.bookKeeperElementTarget == nil
        )
    }
}

extension DragTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: start.elementTarget,
            coordinateOnly: start.elementTarget == nil
        )
    }
}

extension PinchTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

extension RotateTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

extension TwoFingerTapTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

extension DrawPathTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(arguments: heistEvidenceArguments(), coordinateOnly: true)
    }
}

extension DrawBezierTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(arguments: heistEvidenceArguments(), coordinateOnly: true)
    }
}

private extension SwipeGestureSelection {
    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .unitElement(let target, _, _, _):
            return target
        case .point(let start, _):
            return start.elementTarget
        }
    }
}

extension ScrollTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: elementTarget
        )
    }
}

extension ScrollToVisibleTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(elementTarget: elementTarget)
    }
}

extension ElementSearchTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: elementTarget
        )
    }
}

extension ScrollToEdgeTarget {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments(),
            elementTarget: elementTarget
        )
    }
}
