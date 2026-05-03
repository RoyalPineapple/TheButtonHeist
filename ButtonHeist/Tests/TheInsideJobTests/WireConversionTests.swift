#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class WireConverterTests: XCTestCase {

    private typealias WireConversion = TheStash.WireConversion

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPointX: Double = 0,
        activationPointY: Double = 0,
        customContent: [AccessibilityElement.CustomContent] = []
    ) -> AccessibilityElement {
        let uiTraits = UIAccessibilityTraits.fromNames(traits.map(\.rawValue))
        let frame = CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        let activationPoint = CGPoint(x: activationPointX, y: activationPointY)
        return AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: uiTraits,
            identifier: identifier,
            hint: hint,
            userInputLabels: nil,
            shape: .frame(frame),
            activationPoint: activationPoint,
            usesDefaultActivationPoint: activationPointX == 0 && activationPointY == 0,
            customActions: [],
            customContent: customContent,
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    private func makeScreenElement(
        heistId: String,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPointX: Double = 0,
        activationPointY: Double = 0,
        customContent: [AccessibilityElement.CustomContent] = []
    ) -> TheStash.ScreenElement {
        TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: makeElement(
                label: label, value: value, identifier: identifier, hint: hint,
                traits: traits, frameX: frameX, frameY: frameY,
                frameWidth: frameWidth, frameHeight: frameHeight,
                activationPointX: activationPointX, activationPointY: activationPointY,
                customContent: customContent
            ),
            object: nil,
            scrollView: nil
        )
    }

    // MARK: - Trait Mapping

    func testSingleTraitMapped() {
        let traits = WireConversion.traitNames(.button)
        XCTAssertEqual(traits, [.button])
    }

    func testMultipleTraitsMapped() {
        let traits = WireConversion.traitNames([.button, .selected])
        XCTAssertTrue(traits.contains(.button))
        XCTAssertTrue(traits.contains(.selected))
        XCTAssertEqual(traits.count, 2)
    }

    func testBackButtonPrivateTraitMapped() {
        let traits = WireConversion.traitNames(UIAccessibilityTraits(rawValue: 1 << 27))
        XCTAssertEqual(traits, [.backButton])
    }

    func testNoTraitsReturnsEmpty() {
        let traits = WireConversion.traitNames(.none)
        XCTAssertTrue(traits.isEmpty)
    }

    func testTraitMappingDeclarationOrder() {
        let traits = WireConversion.traitNames([.button, .selected])
        XCTAssertEqual(traits[0], .button)
        XCTAssertEqual(traits[1], .selected)
    }

    // MARK: - Trait Name Sync

    func testHeistTraitAllCasesMatchParser() {
        let parserNames = UIAccessibilityTraits.knownTraitNames
        let wireNames = Set(HeistTrait.allCases.map(\.rawValue))
        XCTAssertEqual(wireNames, parserNames,
                       "HeistTrait.allCases must match parser's knownTraitNames")
    }

    // MARK: - Delta: Identical Snapshots

    func testIdenticalSnapshotsReturnNoChange() {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let delta = WireConversion.computeDelta(
            before: elements, after: elements, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
        XCTAssertEqual(delta.elementCount, 1)
        XCTAssertNil(delta.added)
        XCTAssertNil(delta.removed)
        XCTAssertNil(delta.updated)
    }

    func testEmptySnapshotsReturnNoChange() {
        let empty: [TheStash.ScreenElement] = []
        let delta = WireConversion.computeDelta(
            before: empty, after: empty, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
        XCTAssertEqual(delta.elementCount, 0)
    }

    // MARK: - Delta: Element Added

    func testElementAddedProducesElementsChanged() {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let added = makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button])
        let after = before + [added]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.added?.count, 1)
        XCTAssertEqual(delta.added?.first?.heistId, "button_cancel")
        XCTAssertNil(delta.removed)
    }

    // MARK: - Delta: Element Removed

    func testElementRemovedProducesElementsChanged() {
        let before = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button]),
        ]
        let after = [before[0]]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.removed, ["button_cancel"])
        XCTAssertNil(delta.added)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "slider", value: "50%")]
        let after = [makeScreenElement(heistId: "slider", value: "75%")]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 1)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .value)
        XCTAssertEqual(change?.old, "50%")
        XCTAssertEqual(change?.new, "75%")
    }

    func testTraitsChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", traits: [.button])]
        let after = [makeScreenElement(heistId: "btn", traits: [.button, .selected])]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .traits)
        XCTAssertEqual(change?.old, "button")
        XCTAssertEqual(change?.new, "button, selected")
    }

    func testHintChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeScreenElement(heistId: "btn", hint: "Tap to go back")]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .hint)
        XCTAssertEqual(change?.old, "Tap to continue")
        XCTAssertEqual(change?.new, "Tap to go back")
    }

    func testActionsChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "slider", traits: [.button])]
        let after = [makeScreenElement(heistId: "slider", traits: [.adjustable])]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertNotNil(delta.updated)
    }

    func testFrameChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeScreenElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .frame)
        XCTAssertEqual(change?.old, "0,0,100,50")
        XCTAssertEqual(change?.new, "10,20,100,50")
    }

    func testActivationPointChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", activationPointX: 50, activationPointY: 25)]
        let after = [makeScreenElement(heistId: "btn", activationPointX: 75, activationPointY: 40)]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .activationPoint)
        XCTAssertEqual(change?.old, "50,25")
        XCTAssertEqual(change?.new, "75,40")
    }

    func testMultiplePropertyChangesOnSameElement() {
        let before = [makeScreenElement(heistId: "slider", value: "50%", hint: "Volume")]
        let after = [makeScreenElement(heistId: "slider", value: "75%", hint: "Music Volume")]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.updated?.first?.changes.count, 2)
        let properties = delta.updated?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.hint) == true)
    }

    // MARK: - Delta: Label Change Tracking

    func testLabelChangeOnIdentifierMatchedElementProducesUpdate() {
        let before = [makeScreenElement(heistId: "loginButton", label: "Show More", identifier: "loginButton")]
        let after = [makeScreenElement(heistId: "loginButton", label: "Show Less", identifier: "loginButton")]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 1)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .label)
        XCTAssertEqual(change?.old, "Show More")
        XCTAssertEqual(change?.new, "Show Less")
    }

    // MARK: - Delta: Label Change = Add + Remove

    func testLabelChangeProducesAddAndRemove() {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeScreenElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.removed, ["button_ok"])
        XCTAssertEqual(delta.added?.first?.heistId, "button_done")
        XCTAssertNil(delta.updated)
    }

    // MARK: - Delta: Screen Change

    func testScreenChangeReturnsFull() {
        let before = [makeScreenElement(heistId: "button_ok")]
        let afterElement = makeScreenElement(heistId: "header_settings", label: "Settings", traits: [.header])
        let after = [afterElement]
        // The new wire shape derives newInterface from the registry tree, not
        // the flat snapshot — so the tree must reflect after.
        let afterTree: [TheStash.RegistryNode] = [.element(afterElement)]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: afterTree, isScreenChange: true
        )
        XCTAssertEqual(delta.kind, .screenChanged)
        XCTAssertNotNil(delta.newInterface)
        XCTAssertEqual(delta.newInterface?.elements.count, 1)
        XCTAssertEqual(delta.elementCount, 1)
    }

    func testTreeOnlyChangeReturnsStructuralInsertion() {
        let element = makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])
        let beforeTree = [InterfaceNode.element(WireConversion.toWire(element))]
        let container = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 0, width: 320, height: 100)
        )
        let entry = TheStash.RegistryContainerEntry(stableId: "list_0", container: container)
        let afterTree: [TheStash.RegistryNode] = [
            .container(entry, children: [.element(element)])
        ]

        let delta = WireConversion.computeDelta(
            before: [element],
            after: [element],
            beforeTree: beforeTree,
            beforeTreeHash: beforeTree.hashValue,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertNil(delta.newInterface)
        XCTAssertEqual(delta.treeInserted?.count, 1)
        XCTAssertEqual(delta.treeInserted?.first?.location, TreeLocation(parentId: nil, index: 0))
        guard case .container(let info, let children) = delta.treeInserted?.first?.node else {
            return XCTFail("Expected inserted container")
        }
        XCTAssertEqual(info.stableId, "list_0")
        XCTAssertEqual(children.flatten().map(\.heistId), ["button_ok"])
        XCTAssertEqual(
            delta.treeMoved,
            [TreeMove(
                ref: TreeNodeRef(id: "button_ok", kind: .element),
                from: TreeLocation(parentId: nil, index: 0),
                to: TreeLocation(parentId: "list_0", index: 0)
            )]
        )
    }

    func testTreeReorderReturnsMoves() {
        let first = makeScreenElement(heistId: "first", label: "First")
        let second = makeScreenElement(heistId: "second", label: "Second")
        let beforeTree = [
            InterfaceNode.element(WireConversion.toWire(first)),
            InterfaceNode.element(WireConversion.toWire(second)),
        ]
        let afterTree: [TheStash.RegistryNode] = [
            .element(second),
            .element(first),
        ]

        let delta = WireConversion.computeDelta(
            before: [first, second],
            after: [second, first],
            beforeTree: beforeTree,
            beforeTreeHash: beforeTree.hashValue,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertNil(delta.added)
        XCTAssertNil(delta.removed)
        XCTAssertEqual(delta.treeMoved?.count, 2)
        XCTAssertTrue(delta.treeMoved?.contains {
            $0.ref == TreeNodeRef(id: "second", kind: .element)
                && $0.from == TreeLocation(parentId: nil, index: 1)
                && $0.to == TreeLocation(parentId: nil, index: 0)
        } ?? false)
        XCTAssertTrue(delta.treeMoved?.contains {
            $0.ref == TreeNodeRef(id: "first", kind: .element)
                && $0.from == TreeLocation(parentId: nil, index: 0)
                && $0.to == TreeLocation(parentId: nil, index: 1)
        } ?? false)
    }

    func testTreeDeletionReturnsRemovalLocation() {
        let first = makeScreenElement(heistId: "first", label: "First")
        let second = makeScreenElement(heistId: "second", label: "Second")
        let beforeTree = [
            InterfaceNode.element(WireConversion.toWire(first)),
            InterfaceNode.element(WireConversion.toWire(second)),
        ]
        let afterTree: [TheStash.RegistryNode] = [.element(first)]

        let delta = WireConversion.computeDelta(
            before: [first, second],
            after: [first],
            beforeTree: beforeTree,
            beforeTreeHash: beforeTree.hashValue,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.removed, ["second"])
        XCTAssertEqual(
            delta.treeRemoved,
            [TreeRemoval(
                ref: TreeNodeRef(id: "second", kind: .element),
                location: TreeLocation(parentId: nil, index: 1)
            )]
        )
    }

    // MARK: - Delta: Duplicate heistId Pairing

    func testDuplicateHeistIdPairedByIndex() {
        let before = [
            makeScreenElement(heistId: "cell_1", value: "A"),
            makeScreenElement(heistId: "cell_1", value: "B"),
        ]
        let after = [
            makeScreenElement(heistId: "cell_1", value: "X"),
            makeScreenElement(heistId: "cell_1", value: "Y"),
        ]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 2)
        XCTAssertNil(delta.added)
        XCTAssertNil(delta.removed)
    }

    func testDuplicateHeistIdExcessGoesToAddedRemoved() {
        let before = [
            makeScreenElement(heistId: "cell", value: "A"),
            makeScreenElement(heistId: "cell", value: "B"),
            makeScreenElement(heistId: "cell", value: "C"),
        ]
        let after = [
            makeScreenElement(heistId: "cell", value: "X"),
        ]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 1)
        XCTAssertEqual(delta.removed?.count, 2)
    }

    // MARK: - Delta: Empty Diff Coerced to noChange

    func testNoDifferencesCoercedToNoChange() {
        let screenElement = makeScreenElement(heistId: "btn", label: "OK", traits: [.button])

        let delta = WireConversion.computeDelta(
            before: [screenElement], after: [screenElement], afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
    }

    // MARK: - Snapshot Screen Name

    func testSnapshotScreenNameFromHeaderElement() {
        let elements = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "header_settings", label: "Settings", traits: [.header]),
        ]
        XCTAssertEqual(elements.screenName, "Settings")
    }

    func testSnapshotScreenNameNilWhenNoHeader() {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        XCTAssertNil(elements.screenName)
    }

    // MARK: - Custom Content Conversion

    func testCustomContentConvertedToWire() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Size", value: "2.4 MB", isImportant: false),
            .init(label: "Type", value: "PDF", isImportant: true),
        ]
        let element = makeElement(label: "Report", customContent: content)
        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.customContent?.count, 2)
        XCTAssertEqual(wire.customContent?[0].label, "Size")
        XCTAssertEqual(wire.customContent?[0].value, "2.4 MB")
        XCTAssertFalse(wire.customContent?[0].isImportant ?? true)
        XCTAssertEqual(wire.customContent?[1].label, "Type")
        XCTAssertEqual(wire.customContent?[1].value, "PDF")
        XCTAssertTrue(wire.customContent?[1].isImportant ?? false)
    }

    func testEmptyCustomContentConvertedToNil() {
        let element = makeElement(label: "Button", customContent: [])
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    func testEmptyLabelAndValueCustomContentFilteredOut() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Size")
    }

    func testAllEmptyCustomContentConvertedToNil() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    // MARK: - Delta: Custom Content Changes

    func testCustomContentChangeProducesUpdate() {
        let before = [makeScreenElement(
            heistId: "file_report",
            label: "Report",
            customContent: [.init(label: "Size", value: "2.4 MB", isImportant: false)]
        )]
        let after = [makeScreenElement(
            heistId: "file_report",
            label: "Report",
            customContent: [.init(label: "Size", value: "3.1 MB", isImportant: false)]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.old, "Size: 2.4 MB")
        XCTAssertEqual(change?.new, "Size: 3.1 MB")
    }

    func testCustomContentAddedProducesUpdate() {
        let before = [makeScreenElement(heistId: "card", label: "Item")]
        let after = [makeScreenElement(
            heistId: "card",
            label: "Item",
            customContent: [.init(label: "Price", value: "$9.99", isImportant: true)]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertNil(change?.old)
        XCTAssertEqual(change?.new, "Price: $9.99")
    }

    func testCustomContentRemovedProducesUpdate() {
        let before = [makeScreenElement(
            heistId: "card",
            label: "Item",
            customContent: [.init(label: "Price", value: "$9.99", isImportant: true)]
        )]
        let after = [makeScreenElement(heistId: "card", label: "Item")]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.old, "Price: $9.99")
        XCTAssertNil(change?.new)
    }

    func testMultipleCustomContentItemsFormattedCorrectly() {
        let before = [makeScreenElement(heistId: "weather", label: "Portland")]
        let after = [makeScreenElement(
            heistId: "weather",
            label: "Portland",
            customContent: [
                .init(label: "Temperature", value: "58°F", isImportant: true),
                .init(label: "Humidity", value: "82%", isImportant: false),
            ]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.new, "Temperature: 58°F; Humidity: 82%")
    }

    // MARK: - Custom Content: Importance Preserved

    func testImportanceFlagPreservedInConversion() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Price", value: "$79.99", isImportant: true),
            .init(label: "Rating", value: "4.5", isImportant: false),
            .init(label: "Color", value: "Black", isImportant: false),
        ]
        let element = makeElement(label: "Headphones", customContent: content)
        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.customContent?.count, 3)
        XCTAssertTrue(wire.customContent?[0].isImportant ?? false)
        XCTAssertFalse(wire.customContent?[1].isImportant ?? true)
        XCTAssertFalse(wire.customContent?[2].isImportant ?? true)
    }

    // MARK: - Custom Content: Partial Label/Value

    func testLabelOnlyCustomContentPreserved() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Featured", value: "", isImportant: true),
        ]
        let element = makeElement(label: "Item", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Featured")
        XCTAssertEqual(wire.customContent?.first?.value, "")
    }

    func testValueOnlyCustomContentPreserved() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "Available", isImportant: false),
        ]
        let element = makeElement(label: "Item", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "")
        XCTAssertEqual(wire.customContent?.first?.value, "Available")
    }

    // MARK: - Custom Content: Order Preserved

    func testCustomContentOrderPreserved() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Author", value: "Jordan", isImportant: false),
            .init(label: "Type", value: "PDF", isImportant: true),
            .init(label: "Size", value: "2.4 MB", isImportant: false),
            .init(label: "Modified", value: "March 15", isImportant: false),
        ]
        let element = makeElement(label: "Report", customContent: content)
        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.customContent?.count, 4)
        XCTAssertEqual(wire.customContent?[0].label, "Author")
        XCTAssertEqual(wire.customContent?[1].label, "Type")
        XCTAssertEqual(wire.customContent?[2].label, "Size")
        XCTAssertEqual(wire.customContent?[3].label, "Modified")
    }

    // MARK: - Custom Content: Mixed Filter

    func testMixedValidAndEmptyContentFiltersCorrectly() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
            .init(label: "Price", value: "$9.99", isImportant: true),
            .init(label: "", value: "", isImportant: true),
            .init(label: "Color", value: "Red", isImportant: false),
        ]
        let element = makeElement(label: "Product", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 2)
        XCTAssertEqual(wire.customContent?[0].label, "Price")
        XCTAssertTrue(wire.customContent?[0].isImportant ?? false)
        XCTAssertEqual(wire.customContent?[1].label, "Color")
        XCTAssertFalse(wire.customContent?[1].isImportant ?? true)
    }

    // MARK: - Delta: Custom Content Unchanged

    func testIdenticalCustomContentProducesNoChange() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let elements = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: content
        )]

        let delta = WireConversion.computeDelta(
            before: elements, after: elements, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
    }

    // MARK: - Delta: Importance Change

    func testImportanceChangeProducesUpdate() {
        let before = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: [.init(label: "Size", value: "2.4 MB", isImportant: false)]
        )]
        let after = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: [.init(label: "Size", value: "2.4 MB", isImportant: true)]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
    }

    // MARK: - Delta: Custom Content with Other Changes

    func testCustomContentChangeAlongsideValueChange() {
        let before = [makeScreenElement(
            heistId: "product",
            label: "Headphones",
            value: "$79.99",
            customContent: [.init(label: "Stock", value: "In Stock", isImportant: true)]
        )]
        let after = [makeScreenElement(
            heistId: "product",
            label: "Headphones",
            value: "$59.99",
            customContent: [.init(label: "Stock", value: "Low Stock", isImportant: true)]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let properties = delta.updated?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.customContent) == true)
    }

    // MARK: - Delta: Custom Content Label-Only Format

    func testDeltaFormatWithLabelOnly() {
        let before = [makeScreenElement(heistId: "item", label: "Item")]
        let after = [makeScreenElement(
            heistId: "item",
            label: "Item",
            customContent: [.init(label: "Featured", value: "", isImportant: true)]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.new, "Featured")
    }

    func testDeltaFormatWithValueOnly() {
        let before = [makeScreenElement(heistId: "item", label: "Item")]
        let after = [makeScreenElement(
            heistId: "item",
            label: "Item",
            customContent: [.init(label: "", value: "Available", isImportant: false)]
        )]

        let delta = WireConversion.computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.new, "Available")
    }
}

#endif
