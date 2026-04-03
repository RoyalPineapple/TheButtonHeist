#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Float Sanitization

extension CGFloat {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// UIPickerView's 3D-transformed cells can produce non-finite frame coordinates.
    var sanitizedForJSON: CGFloat {
        isFinite ? self : 0
    }
}

// MARK: - Trait Names

extension TheBagman {

    /// Trait-to-name conversion delegated to AccessibilitySnapshotParser.
    /// The parser's `UIAccessibilityTraits.knownTraits` is the single source of truth
    /// for trait naming (22 traits including private traits like textEntry, switchButton).
    /// Strings are mapped to HeistTrait; unknown names are preserved via .unknown().
    func traitNames(_ traits: UIAccessibilityTraits) -> [HeistTrait] {
        traits.traitNames.map { HeistTrait(rawValue: $0) ?? .unknown($0) }
    }
}

// MARK: - Element Conversion

extension TheBagman {

    func convertElement(_ element: AccessibilityElement, object: NSObject? = nil) -> HeistElement {
        let frame = element.shape.frame
        return HeistElement(
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: traitNames(element.traits),
            frameX: frame.origin.x.sanitizedForJSON,
            frameY: frame.origin.y.sanitizedForJSON,
            frameWidth: frame.size.width.sanitizedForJSON,
            frameHeight: frame.size.height.sanitizedForJSON,
            activationPointX: element.activationPoint.x.sanitizedForJSON,
            activationPointY: element.activationPoint.y.sanitizedForJSON,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: element.customContent.isEmpty ? nil : element.customContent.map {
                HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            },
            actions: buildActions(for: element, object: object)
        )
    }

    func buildActions(for element: AccessibilityElement, object: NSObject?) -> [ElementAction] {
        var actions: [ElementAction] = []
        if isInteractive(element: element, object: object) {
            actions.append(.activate)
        }
        if element.traits.contains(.adjustable), isInteractive(element: element, object: object) {
            actions.append(.increment)
            actions.append(.decrement)
        }
        for name in customActionNames(from: object) {
            actions.append(.custom(name))
        }
        return actions
    }
}

// MARK: - Tree Conversion

extension TheBagman {

    func convertHierarchyNode(_ node: AccessibilityHierarchy) -> ElementNode {
        switch node {
        case let .element(_, traversalIndex):
            return .element(order: traversalIndex)
        case let .container(container, children):
            let containerData = convertContainer(container)
            let childNodes = children.map { convertHierarchyNode($0) }
            return .container(containerData, children: childNodes)
        }
    }

    private func convertContainer(_ container: AccessibilityContainer) -> Group {
        let (groupType, label, value, identifier): (GroupType, String?, String?, String?)
        switch container.type {
        case let .semanticGroup(l, v, id):
            groupType = .semanticGroup
            label = l; value = v; identifier = id
        case .list:
            groupType = .list
            label = nil; value = nil; identifier = nil
        case .landmark:
            groupType = .landmark
            label = nil; value = nil; identifier = nil
        case .dataTable:
            groupType = .dataTable
            label = nil; value = nil; identifier = nil
        case .tabBar:
            groupType = .tabBar
            label = nil; value = nil; identifier = nil
        case .scrollable(let contentSize):
            groupType = .scrollable
            label = nil; value = "\(Int(contentSize.width))x\(Int(contentSize.height))"; identifier = nil
        }
        return Group(
            type: groupType,
            label: label,
            value: value,
            identifier: identifier,
            frameX: container.frame.origin.x.sanitizedForJSON,
            frameY: container.frame.origin.y.sanitizedForJSON,
            frameWidth: container.frame.size.width.sanitizedForJSON,
            frameHeight: container.frame.size.height.sanitizedForJSON
        )
    }
}

// MARK: - Interface Delta

extension TheBagman {

    /// Single exit point for elements leaving TheBagman.
    /// Every element returned is added to presentedHeistIds — impossible to send
    /// an element without marking it, eliminating the class of bug where a code path
    /// forgets to set a bookkeeping flag.
    /// Returns ScreenElements sorted by traversal order. Wire conversion happens
    /// at the serialization boundary via `toWire(_:)`.
    func snapshot(_ scope: SnapshotScope) -> [ScreenElement] {
        // Build heistId→order lookup from reverse index for sort ordering
        let orderByHeistId = Dictionary(
            heistIdByTraversalOrder.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [(Int, ScreenElement)] = []
        let candidates: [String] = switch scope {
        case .visible: Array(onScreen)
        case .all: Array(screenElements.keys)
        }
        for heistId in candidates {
            guard let entry = screenElements[heistId] else { continue }
            presentedHeistIds.insert(heistId)
            let order = orderByHeistId[heistId] ?? Int.max
            result.append((order, entry))
        }
        // Sort by traversal order. Off-screen elements (Int.max) sort to the end,
        // with heistId as tiebreaker for deterministic ordering within that group.
        return result.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1.heistId < $1.1.heistId
        }.map(\.1)
    }

    /// Convert a ScreenElement to its wire representation.
    func toWire(_ entry: ScreenElement) -> HeistElement {
        var wire = convertElement(entry.element, object: entry.object)
        wire.heistId = entry.heistId
        return wire
    }

    /// Convert a snapshot to wire format. Use at serialization boundaries.
    func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
        entries.map { toWire($0) }
    }

    // MARK: - Stable ID Synthesis

    /// Trait priority for heistId prefix — most descriptive wins.
    /// Precomputed bitmasks from AccessibilitySnapshotParser's knownTraits.
    private static let traitPriority: [(name: String, mask: UIAccessibilityTraits)] = [
        ("backButton", UIAccessibilityTraits.fromNames(["backButton"])),
        ("searchField", UIAccessibilityTraits.fromNames(["searchField"])),
        ("textEntry", UIAccessibilityTraits.fromNames(["textEntry"])),
        ("switchButton", UIAccessibilityTraits.fromNames(["switchButton"])),
        ("adjustable", .adjustable),
        ("button", .button),
        ("link", .link),
        ("image", .image),
        ("header", .header),
        ("tabBar", UIAccessibilityTraits.fromNames(["tabBar"])),
    ]

    /// Assign deterministic `heistId` to each AccessibilityElement.
    /// Developer-provided identifiers take priority — they become the heistId directly.
    /// Synthesized IDs use `{trait}_{slug}` with label for the slug (value excluded for stability).
    /// Duplicates get `_1`, `_2` suffixes in traversal order — all instances, not just the second.
    /// Returns the heistId array, parallel to the input elements array.
    func assignHeistIds(_ elements: [AccessibilityElement]) -> [String] {
        // Phase 1: generate base IDs
        var heistIds = elements.map { element -> String in
            if let identifier = element.identifier, !identifier.isEmpty {
                return identifier
            }
            return synthesizeBaseId(element)
        }

        // Phase 2: disambiguate duplicates
        var counts: [String: Int] = [:]
        for heistId in heistIds {
            counts[heistId, default: 0] += 1
        }

        var seen: [String: Int] = [:]
        for i in heistIds.indices {
            let base = heistIds[i]
            if let count = counts[base], count > 1 {
                let index = seen[base, default: 0] + 1
                seen[base] = index
                heistIds[i] = "\(base)_\(index)"
            }
        }

        return heistIds
    }

    func synthesizeBaseId(_ element: AccessibilityElement) -> String {
        let traitPrefix = Self.traitPriority.first { element.traits.contains($0.mask) }?.name
            ?? (element.label != nil ? HeistTrait.staticText.rawValue : "element")

        // Value is intentionally excluded — it changes on interaction (toggles,
        // sliders, checkboxes) and must not affect element identity.
        // Strip leading words that duplicate the trait prefix before slugifying:
        // "Switch Button Off" with prefix "switchButton" → slug of "Off" → "off"
        let labelForSlug = stripTraitPrefix(element.label, traitPrefix: traitPrefix)
            ?? element.label
        let slug = slugify(labelForSlug)
            ?? slugify(element.description)

        if let slug {
            return "\(traitPrefix)_\(slug)"
        }
        return traitPrefix
    }

    /// Strip leading words from text that duplicate the trait prefix.
    /// "Switch Button Off" with prefix "switchButton" → "Off"
    /// Returns nil if stripping would leave nothing (label IS the trait name).
    func stripTraitPrefix(_ text: String?, traitPrefix: String) -> String? {
        guard let text else { return nil }
        let prefixWords = traitPrefix
            .replacing(/([a-z])([A-Z])/, with: { "\($0.output.1) \($0.output.2)" })
            .lowercased()
            .split(separator: " ")
        let textWords = text.split(separator: " ", omittingEmptySubsequences: true)
        guard textWords.count > prefixWords.count else { return nil }
        for (prefixWord, textWord) in zip(prefixWords, textWords) {
            guard textWord.lowercased() == prefixWord else { return nil }
        }
        let remainder = textWords.dropFirst(prefixWords.count).joined(separator: " ")
        return remainder.isEmpty ? nil : remainder
    }

    func slugify(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let slug = text.lowercased()
            .replacing(/[^a-z0-9]+/, with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !slug.isEmpty else { return nil }
        return String(slug.prefix(24))
    }

    /// Compare two element snapshots and return a compact delta.
    ///
    /// Screen change detection is done by the caller via view controller identity —
    /// `isScreenChange` is true when the screen changed (VC identity or topology). This function handles
    /// the response payloads:
    /// - screen_changed → full new interface
    /// - elements_changed → added/removed/updated diff
    /// - no_change → element count only
    func computeDelta(
        before: [ScreenElement],
        after: [ScreenElement],
        afterTree: [AccessibilityHierarchy]?,
        isScreenChange: Bool
    ) -> InterfaceDelta {
        // Screen changed: VC identity differs → return full new interface
        if isScreenChange {
            let afterWire = toWire(after)
            let tree = afterTree?.map { convertHierarchyNode($0) }
            let fullInterface = Interface(timestamp: Date(), elements: afterWire, tree: tree)
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: afterWire.count,
                newInterface: fullInterface
            )
        }

        // Fast no-change check on internal types — compares heistId + AccessibilityElement
        // (both Hashable) without wire conversion. This is the hot path for Pulse polling
        // where most cycles produce no change.
        if before.count == after.count {
            var unchanged = true
            for index in before.indices {
                if before[index].heistId != after[index].heistId
                    || before[index].element != after[index].element {
                    unchanged = false
                    break
                }
            }
            if unchanged {
                return InterfaceDelta(kind: .noChange, elementCount: after.count)
            }
        }

        // Something changed — convert to wire for property-level diff
        let beforeWire = toWire(before)
        var afterWire = toWire(after)

        // Recover elements that scrolled off screen during a layout shift.
        // If an element was visible before the action but is no longer in the
        // visible after-snapshot, check the full registry. If it still exists
        // (just off-screen), include its current state so the delta reports it
        // as "updated" rather than "removed."
        let afterHeistIds = Set(afterWire.map(\.heistId))
        for beforeElement in beforeWire where !afterHeistIds.contains(beforeElement.heistId) {
            if let entry = screenElements[beforeElement.heistId] {
                afterWire.append(toWire(entry))
            }
        }

        return computeElementDelta(beforeEls: beforeWire, afterEls: afterWire)
    }

    /// Semantic element diff — heistId is the sole matching key.
    ///
    /// heistId encodes developer identifiers or synthesized trait+label (value excluded).
    /// For identifier-matched elements, label changes surface as property updates.
    /// For synthesized IDs, label changes produce different heistIds and appear as remove + add.
    ///
    /// Returns added/removed/updated categories. Updated elements carry per-property diffs.
    private func computeElementDelta(
        beforeEls: [HeistElement],
        afterEls: [HeistElement]
    ) -> InterfaceDelta {
        let oldByHeistId = Dictionary(grouping: beforeEls, by: \.heistId)
        let newByHeistId = Dictionary(grouping: afterEls, by: \.heistId)
        let allHeistIds = Set(oldByHeistId.keys).union(newByHeistId.keys)

        var updated: [ElementUpdate] = []
        var added: [HeistElement] = []
        var removed: [String] = []

        for hid in allHeistIds {
            let oldEls = oldByHeistId[hid] ?? []
            let newEls = newByHeistId[hid] ?? []
            let pairCount = min(oldEls.count, newEls.count)
            for i in 0..<pairCount {
                if let update = buildElementUpdate(old: oldEls[i], new: newEls[i]) {
                    updated.append(update)
                }
            }
            for i in pairCount..<oldEls.count {
                removed.append(oldEls[i].heistId)
            }
            for i in pairCount..<newEls.count {
                added.append(newEls[i])
            }
        }

        if added.isEmpty && removed.isEmpty && updated.isEmpty {
            return InterfaceDelta(kind: .noChange, elementCount: afterEls.count)
        }

        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: afterEls.count,
            added: added.isEmpty ? nil : added,
            removed: removed.isEmpty ? nil : removed,
            updated: updated.isEmpty ? nil : updated
        )
    }

    /// Build an ElementUpdate if any mutable property differs.
    private func buildElementUpdate(old: HeistElement, new: HeistElement) -> ElementUpdate? {
        var changes: [PropertyChange] = []

        if old.label != new.label {
            changes.append(PropertyChange(property: .label, old: old.label, new: new.label))
        }
        if old.value != new.value {
            changes.append(PropertyChange(property: .value, old: old.value, new: new.value))
        }
        if old.traits != new.traits {
            let oldTraits = old.traits.map(\.rawValue).joined(separator: ", ")
            let newTraits = new.traits.map(\.rawValue).joined(separator: ", ")
            changes.append(PropertyChange(property: .traits, old: oldTraits, new: newTraits))
        }
        if old.hint != new.hint {
            changes.append(PropertyChange(property: .hint, old: old.hint, new: new.hint))
        }
        if old.actions != new.actions {
            let oldActions = old.actions.map(\.description).joined(separator: ", ")
            let newActions = new.actions.map(\.description).joined(separator: ", ")
            changes.append(PropertyChange(property: .actions, old: oldActions, new: newActions))
        }
        let oldFrame = "\(Int(old.frameX)),\(Int(old.frameY)),\(Int(old.frameWidth)),\(Int(old.frameHeight))"
        let newFrame = "\(Int(new.frameX)),\(Int(new.frameY)),\(Int(new.frameWidth)),\(Int(new.frameHeight))"
        if oldFrame != newFrame {
            changes.append(PropertyChange(property: .frame, old: oldFrame, new: newFrame))
        }
        let oldAP = "\(Int(old.activationPointX)),\(Int(old.activationPointY))"
        let newAP = "\(Int(new.activationPointX)),\(Int(new.activationPointY))"
        if oldAP != newAP {
            changes.append(PropertyChange(property: .activationPoint, old: oldAP, new: newAP))
        }

        guard !changes.isEmpty else { return nil }
        return ElementUpdate(heistId: new.heistId, changes: changes)
    }

}

// MARK: - Array Helpers

extension Array where Element == HeistElement {
    /// Label of the first header-traited element (screen name hint).
    var screenName: String? {
        first { $0.traits.contains(.header) }?.label
    }
}

extension Array where Element == TheBagman.ScreenElement {
    /// Label of the first header-traited element (screen name hint).
    var screenName: String? {
        first { $0.element.traits.contains(.header) }?.element.label
    }
}

// MARK: - Shape Helper

extension AccessibilityElement.Shape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect
        case let .path(path): return path.bounds
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
