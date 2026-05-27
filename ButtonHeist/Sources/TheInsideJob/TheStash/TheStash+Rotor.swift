#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore

// MARK: - Rotor Actions

@MainActor
final class RotorContinuationStore {
    private var state: PendingRotorState = .none

    func store(screenElement: TheStash.ScreenElement, object: NSObject) {
        state = .stored(PendingRotorResult(
            token: UUID(),
            screenElement: screenElement,
            object: object
        ))
    }

    func prepare(targetedHeistId: HeistId?) -> UUID? {
        let pending: PendingRotorResult
        switch state {
        case .none:
            return nil
        case .stored(let result), .active(let result):
            pending = result
        }
        guard targetedHeistId == pending.screenElement.heistId else {
            clear()
            return nil
        }
        state = .active(pending)
        return pending.token
    }

    func activeCursorObject(heistId: HeistId) -> NSObject? {
        guard case .active(let pendingRotorResult) = state,
              pendingRotorResult.screenElement.heistId == heistId else {
            return nil
        }
        return pendingRotorResult.object
    }

    func clear() {
        state = .none
    }

    func clear(consumedToken: UUID) {
        switch state {
        case .none:
            return
        case .stored(let pending):
            if pending.token == consumedToken {
                clear()
            }
            return
        case .active(let pending):
            if pending.token == consumedToken {
                clear()
            } else {
                state = .stored(pending)
            }
        }
    }

    private struct PendingRotorResult {
        let token: UUID
        let screenElement: TheStash.ScreenElement
        /// Strongly retain out-of-tree rotor result objects for one rotor
        /// continuation step. `LiveInterface` refs are weak, but VoiceOver-style
        /// next/previous needs the current item object as rotor-only cursor
        /// state.
        let object: NSObject
    }

    private enum PendingRotorState {
        case none
        case stored(PendingRotorResult)
        case active(PendingRotorResult)
    }
}

extension TheStash {

    struct RotorHit {
        let rotor: String
        let screenElement: ScreenElement?
        let textRange: RotorTextRange?
    }

    enum RotorOutcome {
        case succeeded(RotorHit)
        case deallocated
        case noRotors
        case noSuchRotor(available: [String])
        case ambiguousRotor(available: [String])
        case currentItemUnavailable(String)
        case currentTextRangeUnavailable
        case noResult(String)
        case resultTargetUnavailable(String)
        case resultTargetNotParsed(String)
    }

    func performRotor(
        rotor: String?,
        rotorIndex: Int?,
        currentHeistId: HeistId?,
        currentTextRange: TextRangeReference?,
        direction: RotorDirection,
        on liveTarget: LiveActionTarget
    ) -> RotorOutcome {
        let object = liveTarget.object
        let rotors = object.accessibilityCustomRotors ?? []
        guard !rotors.isEmpty else { return .noRotors }

        let availableNames = rotors.map { $0.bhInvocableName(locale: object.accessibilityLanguage) }
        let selection: UIAccessibilityCustomRotor
        if let rotorIndex {
            guard rotors.indices.contains(rotorIndex) else {
                return .noSuchRotor(available: availableNames)
            }
            selection = rotors[rotorIndex]
        } else if let rotorName = rotor {
            let matches = rotors.enumerated().filter {
                $0.element.bhInvocableName(locale: object.accessibilityLanguage) == rotorName
            }
            switch matches.count {
            case 0:
                return .noSuchRotor(available: availableNames)
            case 1:
                selection = matches[0].element
            default:
                return .ambiguousRotor(available: availableNames)
            }
        } else if rotors.count == 1 {
            selection = rotors[0]
        } else {
            return .ambiguousRotor(available: availableNames)
        }

        let predicate = UIAccessibilityCustomRotorSearchPredicate()
        predicate.searchDirection = direction.uiAccessibilityDirection
        if let currentHeistId {
            guard let currentObject = rotorCurrentObject(heistId: currentHeistId) else {
                return .currentItemUnavailable(currentHeistId)
            }
            let currentRange: UITextRange?
            if let currentTextRange {
                guard let input = currentObject as? UITextInput,
                      let range = textRange(from: currentTextRange, in: input) else {
                    return .currentTextRangeUnavailable
                }
                currentRange = range
            } else {
                currentRange = nil
            }
            predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: currentObject, targetRange: currentRange)
        } else if currentTextRange != nil {
            return .currentTextRangeUnavailable
        }

        let rotorName = selection.bhInvocableName(locale: object.accessibilityLanguage)
        guard let result = selection.itemSearchBlock(predicate) else {
            return .noResult(rotorName)
        }
        let resultObject = result.targetElement as? NSObject
        let textRange = result.targetRange.map { describeTextRange($0, in: resultObject) }
        guard let resultObject else {
            return .resultTargetUnavailable(rotorName)
        }
        let parsed = parseRotorResultObject(resultObject)
        if let parsed, !parsed.isInCurrentHierarchy {
            rotorContinuations.store(screenElement: parsed.screenElement, object: resultObject)
        }
        guard parsed != nil || textRange != nil else {
            return .resultTargetNotParsed(rotorName)
        }
        return .succeeded(RotorHit(rotor: rotorName, screenElement: parsed?.screenElement, textRange: textRange))
    }

    func preparePendingRotorResult(targetedHeistId: HeistId?) -> UUID? {
        rotorContinuations.prepare(targetedHeistId: targetedHeistId)
    }

    func clearPendingRotorResult() {
        rotorContinuations.clear()
    }

    func clearPendingRotorResult(consumedToken: UUID) {
        rotorContinuations.clear(consumedToken: consumedToken)
    }

    func rotorCurrentObject(heistId: HeistId) -> NSObject? {
        if let pendingObject = rotorContinuations.activeCursorObject(heistId: heistId) {
            return pendingObject
        }
        guard let current = resolveVisibleTarget(.heistId(heistId)).resolved?.screenElement,
              let currentObject = liveObject(for: current) else {
            return nil
        }
        return currentObject
    }
}

private extension TheStash {

    struct ParsedRotorResultObject {
        let screenElement: ScreenElement
        let isInCurrentHierarchy: Bool
    }

    /// Return the known `ScreenElement` corresponding to a UIKit accessibility
    /// object by live object identity.
    func knownObject(_ object: NSObject) -> ParsedRotorResultObject? {
        guard let heistId = currentScreen.liveInterface.elementRefs.first(where: { _, ref in
            ref.object === object
        })?.key,
            let cached = currentScreen.findElement(heistId: heistId)
        else {
            return nil
        }
        return ParsedRotorResultObject(
            screenElement: cached,
            isInCurrentHierarchy: visibleIds.contains(cached.heistId)
        )
    }

    /// Parse the live hierarchy and return the `ScreenElement` corresponding to
    /// a UIKit accessibility object. Used by live custom rotor steps so the
    /// returned rotor target flows through the same parser as `get_interface`.
    func parseLiveObject(_ object: NSObject) -> ScreenElement? {
        guard let result = burglar.parse() else { return nil }
        guard let parsedElement = result.objects.first(where: { pair in
            pair.value === object
        })?.key else {
            return nil
        }
        let screen = TheBurglar.buildScreen(from: result)
        guard let heistId = screen.liveInterface.heistIdByElement[parsedElement] else { return nil }
        return screen.elements[heistId]
    }

    func parseRotorResultObject(_ object: NSObject) -> ParsedRotorResultObject? {
        if let known = knownObject(object) {
            return known
        }

        let standaloneElement = burglar.parseObject(object)
        if let screenElement = parseLiveObject(object) {
            return ParsedRotorResultObject(screenElement: screenElement, isInCurrentHierarchy: true)
        }

        if let standaloneElement,
           let known = knownCachedRotorResult(matching: standaloneElement) {
            return known
        }

        guard let element = standaloneElement else { return nil }
        let heistId = pendingRotorHeistId(for: element)
        return ParsedRotorResultObject(
            screenElement: ScreenElement(
                heistId: heistId,
                contentSpaceOrigin: nil,
                element: element
            ),
            isInCurrentHierarchy: false
        )
    }

    func knownCachedRotorResult(matching rotorElement: AccessibilityElement) -> ParsedRotorResultObject? {
        let candidates = selectElements().filter {
            !visibleIds.contains($0.heistId)
                && Self.matchesCachedRotorResult(knownElement: $0.element, rotorElement: rotorElement)
        }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        return ParsedRotorResultObject(screenElement: candidate, isInCurrentHierarchy: false)
    }

    static func matchesCachedRotorResult(
        knownElement: AccessibilityElement,
        rotorElement: AccessibilityElement
    ) -> Bool {
        guard rotorElement.label?.isEmpty == false
                || rotorElement.value?.isEmpty == false
                || rotorElement.identifier?.isEmpty == false else {
            return false
        }
        guard optionalText(knownElement.label, matches: rotorElement.label),
              optionalText(knownElement.value, matches: rotorElement.value),
              stableTraitNames(knownElement.traits) == stableTraitNames(rotorElement.traits),
              framesApproximatelyMatch(knownElement.shape.frame, rotorElement.shape.frame) else {
            return false
        }
        if let knownIdentifier = knownElement.identifier, !knownIdentifier.isEmpty,
           let rotorIdentifier = rotorElement.identifier, !rotorIdentifier.isEmpty {
            return ElementMatcher.stringEquals(knownIdentifier, rotorIdentifier)
        }
        return true
    }

    static func optionalText(_ lhs: String?, matches rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return ElementMatcher.stringEquals(lhs, rhs)
        default:
            return false
        }
    }

    static func stableTraitNames(_ traits: AccessibilityTraits) -> Set<String> {
        Set(traits.traitNames).subtracting(AccessibilityPolicy.transientTraitNames)
    }

    static func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        guard !lhs.isNull, !lhs.isEmpty,
              !rhs.isNull, !rhs.isEmpty,
              lhs.origin.x.isFinite,
              lhs.origin.y.isFinite,
              lhs.size.width.isFinite,
              lhs.size.height.isFinite,
              rhs.origin.x.isFinite,
              rhs.origin.y.isFinite,
              rhs.size.width.isFinite,
              rhs.size.height.isFinite else {
            return false
        }
        let tolerance: CGFloat = 1
        return abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    func pendingRotorHeistId(for element: AccessibilityElement) -> HeistId {
        let base = Self.IdAssignment.assign([element]).first ?? "element"
        let root = "rotor_result_\(base)"
        var candidate = root
        var suffix = 2
        let knownHeistIds = currentScreen.knownInterface.heistIds
        while knownHeistIds.contains(candidate) {
            candidate = "\(root)_\(suffix)"
            suffix += 1
        }
        return candidate
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
    func bhInvocableName(locale: String?) -> String {
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
