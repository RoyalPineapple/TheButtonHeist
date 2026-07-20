#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

// MARK: - Rotor Actions

extension TheVault {

    struct RotorHit: Sendable {
        let rotor: RotorName
        let treeElement: InterfaceTree.Element?
        let textRange: RotorTextRange?
    }

    enum RotorOutcome: Sendable {
        case succeeded(RotorHit)
        case deallocated
        case noRotors
        case noSuchRotor(available: [RotorName])
        case ambiguousRotor(available: [RotorName])
        case continuationInvalidated
        case currentItemUnavailable(String)
        case continuationTextRangeUnavailable
        case noResult(RotorName)
        case resultTargetUnavailable(RotorName)
        case resultTargetUnresolved(RotorName)
    }

    func performRotor(
        selection rotorSelection: RotorSelection,
        direction: RotorDirection,
        on liveTarget: LiveActionTarget
    ) -> RotorOutcome {
        let object = liveTarget.object
        let rotors = object.accessibilityCustomRotors ?? []
        guard !rotors.isEmpty else { return .noRotors }

        let availableNames = rotors.compactMap { $0.bhInvocableName(locale: object.accessibilityLanguage) }
        let selection: UIAccessibilityCustomRotor
        switch rotorSelection {
        case .index(let rotorIndex):
            guard rotors.indices.contains(rotorIndex.value) else {
                return .noSuchRotor(available: availableNames)
            }
            selection = rotors[rotorIndex.value]
        case .named(let rotorName):
            let matches = rotors.enumerated().filter {
                $0.element.bhInvocableName(locale: object.accessibilityLanguage) == .some(rotorName)
            }
            switch matches.count {
            case 0:
                return .noSuchRotor(available: availableNames)
            case 1:
                selection = matches[0].element
            default:
                return .ambiguousRotor(available: availableNames)
            }
        case .automatic:
            if rotors.count == 1 {
                selection = rotors[0]
            } else {
                return .ambiguousRotor(available: availableNames)
            }
        }

        guard let rotorName = selection.bhInvocableName(locale: object.accessibilityLanguage) else {
            return .noSuchRotor(available: availableNames)
        }
        let hostHeistId = liveTarget.treeElement.heistId

        let predicate = UIAccessibilityCustomRotorSearchPredicate()
        predicate.searchDirection = direction.uiAccessibilityDirection
        // A different host or rotor starts a new traversal. A continuation on
        // the same host and rotor must resolve against the current observation;
        // losing that evidence is an explicit failure, never an implicit reset.
        if let cursor = rotorCursor,
           cursor.hostHeistId == hostHeistId,
           cursor.rotorName == rotorName {
            guard cursor.generation == currentRotorGeneration else {
                rotorCursor = nil
                return .continuationInvalidated
            }
            guard let currentObject = currentLiveCapture.object(for: cursor.selectionHeistId) else {
                rotorCursor = nil
                return .currentItemUnavailable(cursor.selectionHeistId.rawValue)
            }
            let currentRange: UITextRange?
            if let reference = cursor.textRange {
                guard let input = currentObject as? UITextInput,
                      let range = textRange(from: reference, in: input) else {
                    rotorCursor = nil
                    return .continuationTextRangeUnavailable
                }
                currentRange = range
            } else {
                currentRange = nil
            }
            predicate.currentItem = UIAccessibilityCustomRotorItemResult(
                targetElement: currentObject,
                targetRange: currentRange
            )
        }

        guard let result = selection.itemSearchBlock(predicate) else {
            return .noResult(rotorName)
        }
        let resultObject = result.targetElement as? NSObject
        let textRange = result.targetRange.map { describeTextRange($0, in: resultObject) }
        guard let resultObject else {
            return .resultTargetUnavailable(rotorName)
        }
        let resolved = resolveRotorResultObject(resultObject)
        guard let resolved else {
            return .resultTargetUnresolved(rotorName)
        }
        let cursorTextRange: TextRangeReference?
        if let targetRange = result.targetRange {
            guard let reference = describeTextRangeReference(targetRange, in: resultObject) else {
                rotorCursor = nil
                return .continuationTextRangeUnavailable
            }
            cursorTextRange = reference
        } else {
            cursorTextRange = nil
        }
        rotorCursor = RotorCursor(
            hostHeistId: hostHeistId,
            rotorName: rotorName,
            generation: currentRotorGeneration,
            selectionHeistId: resolved.heistId,
            textRange: cursorTextRange
        )
        return .succeeded(RotorHit(rotor: rotorName, treeElement: resolved, textRange: textRange))
    }
}

private extension TheVault {

    var currentRotorGeneration: ScreenGeneration {
        semanticObservationStream.latestCommittedEvent?.generation ?? .initial
    }

    /// Return the known `InterfaceTree.Element` corresponding to a UIKit accessibility
    /// object by live object identity.
    func knownObject(_ object: NSObject) -> InterfaceTree.Element? {
        guard let heistId = liveElementHeistId(matching: object),
            let cached = interfaceElement(heistId: heistId)
        else {
            return nil
        }
        return cached
    }

    /// Capture the live hierarchy and resolve the `InterfaceTree.Element` corresponding to
    /// a UIKit accessibility object. Used by live custom rotor steps so the
    /// returned rotor target flows through the same parser as `get_interface`.
    func resolveLiveObject(_ object: NSObject) -> InterfaceTree.Element? {
        guard let observation = refreshLiveCapture() else { return nil }
        guard let heistId = observation.liveCapture.heistId(matching: object) else { return nil }
        return observation.tree.findElement(heistId: heistId)
    }

    func resolveRotorResultObject(_ object: NSObject) -> InterfaceTree.Element? {
        if let known = knownObject(object) {
            return known
        }

        return resolveLiveObject(object)
    }

    func textRange(from reference: TextRangeReference, in input: UITextInput) -> UITextRange? {
        guard let start = input.position(from: input.beginningOfDocument, offset: reference.startOffset),
              let end = input.position(from: input.beginningOfDocument, offset: reference.endOffset) else {
            return nil
        }
        return input.textRange(from: start, to: end)
    }

    func describeTextRange(_ range: UITextRange, in object: NSObject?) -> RotorTextRange {
        guard let input = object as? UITextInput else {
            return RotorTextRange(rangeDescription: "\(range)")
        }

        let startOffset = input.offset(from: input.beginningOfDocument, to: range.start)
        let endOffset = input.offset(from: input.beginningOfDocument, to: range.end)
        return RotorTextRange(
            text: input.text(in: range),
            startOffset: startOffset,
            endOffset: endOffset,
            rangeDescription: "[\(startOffset)..<\(endOffset)]"
        )
    }

    func describeTextRangeReference(_ range: UITextRange, in object: NSObject) -> TextRangeReference? {
        guard let input = object as? UITextInput else { return nil }
        return TextRangeReference(
            startOffset: input.offset(from: input.beginningOfDocument, to: range.start),
            endOffset: input.offset(from: input.beginningOfDocument, to: range.end)
        )
    }
}

private extension RotorDirection {
    var uiAccessibilityDirection: UIAccessibilityCustomRotor.Direction {
        switch self {
        case .next:
            return .next
        case .previous:
            return .previous
        }
    }
}

extension UIAccessibilityCustomRotor {
    func bhInvocableName(locale: String?) -> RotorName? {
        let value = bhInvocableNameText(locale: locale)
        return try? RotorName(validating: value)
    }

    private func bhInvocableNameText(locale: String?) -> String {
        guard name.isEmpty else { return name }

        switch systemRotorType {
        case .none:
            return localizedRotorName(defaultValue: "None", key: "rotor.none.description", locale: locale)
        case .link:
            return localizedRotorName(defaultValue: "Links", key: "rotor.link.description", locale: locale)
        case .visitedLink:
            return localizedRotorName(defaultValue: "Visited Links", key: "rotor.visited_link.description", locale: locale)
        case .heading:
            return localizedRotorName(defaultValue: "Headings", key: "rotor.heading.description", locale: locale)
        case .headingLevel1:
            return localizedRotorName(defaultValue: "Heading 1", key: "rotor.heading_level1.description", locale: locale)
        case .headingLevel2:
            return localizedRotorName(defaultValue: "Heading 2", key: "rotor.heading_level2.description", locale: locale)
        case .headingLevel3:
            return localizedRotorName(defaultValue: "Heading 3", key: "rotor.heading_level3.description", locale: locale)
        case .headingLevel4:
            return localizedRotorName(defaultValue: "Heading 4", key: "rotor.heading_level4.description", locale: locale)
        case .headingLevel5:
            return localizedRotorName(defaultValue: "Heading 5", key: "rotor.heading_level5.description", locale: locale)
        case .headingLevel6:
            return localizedRotorName(defaultValue: "Heading 6", key: "rotor.heading_level6.description", locale: locale)
        case .boldText:
            return localizedRotorName(defaultValue: "Bold Text", key: "rotor.bold_text.description", locale: locale)
        case .italicText:
            return localizedRotorName(defaultValue: "Italic Text", key: "rotor.italic_text.description", locale: locale)
        case .underlineText:
            return localizedRotorName(defaultValue: "Underlined Text", key: "rotor.underline_text.description", locale: locale)
        case .misspelledWord:
            return localizedRotorName(defaultValue: "Misspelled Words", key: "rotor.misspelled_word.description", locale: locale)
        case .image:
            return localizedRotorName(defaultValue: "Images", key: "rotor.image.description", locale: locale)
        case .textField:
            return localizedRotorName(defaultValue: "Text Fields", key: "rotor.text_field.description", locale: locale)
        case .table:
            return localizedRotorName(defaultValue: "Tables", key: "rotor.table.description", locale: locale)
        case .list:
            return localizedRotorName(defaultValue: "Lists", key: "rotor.list.description", locale: locale)
        case .landmark:
            return localizedRotorName(defaultValue: "Landmarks", key: "rotor.landmark.description", locale: locale)
        @unknown default:
            let format = localizedRotorName(
                defaultValue: "Unknown Rotor Type, Raw value: %lld",
                key: "rotor.unknown.description_format",
                locale: locale
            )
            return String(format: format, systemRotorType.rawValue)
        }
    }

    private func localizedRotorName(defaultValue: String, key: String, locale: String?) -> String {
        StringLocalization.preferredBundle(for: locale).localizedString(forKey: key, value: defaultValue, table: nil)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
