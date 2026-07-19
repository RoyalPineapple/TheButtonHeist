#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension WireConverterTests {
    // MARK: - Custom Content Conversion

    func testCustomContentConvertedToWire() throws {
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

    func testEmptyCustomContentConvertedToNil() throws {
        let element = makeElement(label: "Button", customContent: [])
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    func testEmptyLabelAndValueCustomContentFilteredOut() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Size")
    }

    func testAllEmptyCustomContentConvertedToNil() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    // MARK: - Custom Rotor Conversion

    func testCustomRotorsConvertedToWire() throws {
        let element = makeElement(
            label: "Validation Results",
            customRotors: [
                .init(name: "Errors"),
                .init(name: "Warnings"),
            ]
        )

        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.rotors, [
            HeistRotor(name: "Errors"),
            HeistRotor(name: "Warnings"),
        ])
    }

    func testEmptyCustomRotorNamesFilteredOut() throws {
        let element = makeElement(
            label: "Validation Results",
            customRotors: [
                .init(name: ""),
                .init(name: "Errors"),
            ]
        )

        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.rotors, [HeistRotor(name: "Errors")])
    }

    func testNoCustomRotorsConvertedToNil() throws {
        let element = makeElement(label: "Validation Results")
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.rotors)
    }

    func testCustomRotorChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "results", label: "Validation Results")]
        let after = [makeScreenElement(
            heistId: "results",
            label: "Validation Results",
            customRotors: [.init(name: "Errors")]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .rotors)
        XCTAssertNil(change?.oldDisplayText)
        XCTAssertEqual(change?.newDisplayText, "Errors")
    }

    // MARK: - Delta: Custom Content Changes

    func testCustomContentChangeProducesUpdate() throws {
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

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.oldDisplayText, "Size: 2.4 MB")
        XCTAssertEqual(change?.newDisplayText, "Size: 3.1 MB")
    }

    func testCustomContentAddedProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "card", label: "Item")]
        let after = [makeScreenElement(
            heistId: "card",
            label: "Item",
            customContent: [.init(label: "Price", value: "$9.99", isImportant: true)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertNil(change?.oldDisplayText)
        XCTAssertEqual(change?.newDisplayText, "Price: $9.99")
    }

    func testCustomContentRemovedProducesUpdate() throws {
        let before = [makeScreenElement(
            heistId: "card",
            label: "Item",
            customContent: [.init(label: "Price", value: "$9.99", isImportant: true)]
        )]
        let after = [makeScreenElement(heistId: "card", label: "Item")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.oldDisplayText, "Price: $9.99")
        XCTAssertNil(change?.newDisplayText)
    }

    func testMultipleCustomContentItemsFormattedCorrectly() throws {
        let before = [makeScreenElement(heistId: "weather", label: "Portland")]
        let after = [makeScreenElement(
            heistId: "weather",
            label: "Portland",
            customContent: [
                .init(label: "Temperature", value: "58°F", isImportant: true),
                .init(label: "Humidity", value: "82%", isImportant: false),
            ]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.newDisplayText, "Temperature: 58°F; Humidity: 82%")
    }

    // MARK: - Custom Content: Importance Preserved

    func testImportanceFlagPreservedInConversion() throws {
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

    func testLabelOnlyCustomContentPreserved() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Featured", value: "", isImportant: true),
        ]
        let element = makeElement(label: "Item", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Featured")
        XCTAssertEqual(wire.customContent?.first?.value, "")
    }

    func testValueOnlyCustomContentPreserved() throws {
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

    func testCustomContentOrderPreserved() throws {
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

    func testMixedValidAndEmptyContentFiltersCorrectly() throws {
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

    func testIdenticalCustomContentProducesNoChange() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let elements = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: content
        )]

        let delta = computeDelta(
            before: elements, after: elements, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertTrue(delta.changeFacts.isEmpty)
    }

    // MARK: - Delta: Importance Change

    func testImportanceChangeProducesUpdate() throws {
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

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
    }

    // MARK: - Delta: Custom Content with Other Changes

    func testCustomContentChangeAlongsideValueChange() throws {
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

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let properties = delta.testEdits.updatedOptional?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.customContent) == true)
    }

    // MARK: - Delta: Custom Content Label-Only Format

    func testDeltaFormatWithLabelOnly() throws {
        let before = [makeScreenElement(heistId: "item", label: "Item")]
        let after = [makeScreenElement(
            heistId: "item",
            label: "Item",
            customContent: [.init(label: "Featured", value: "", isImportant: true)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.newDisplayText, "Featured")
    }

    func testDeltaFormatWithValueOnly() throws {
        let before = [makeScreenElement(heistId: "item", label: "Item")]
        let after = [makeScreenElement(
            heistId: "item",
            label: "Item",
            customContent: [.init(label: "", value: "Available", isImportant: false)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.newDisplayText, "Available")
    }
}

#endif
