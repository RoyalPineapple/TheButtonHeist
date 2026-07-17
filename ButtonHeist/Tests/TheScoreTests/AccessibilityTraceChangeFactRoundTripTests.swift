import ButtonHeistTestSupport
import XCTest
import AccessibilitySnapshotModel
@testable import TheScore

// MARK: - AccessibilityTrace.ChangeFact Round-Trip Tests

/// Wire-shape gate for canonical facts derived from durable trace captures.
final class AccessibilityTraceChangeFactRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Fact-free windows

    func testCompleteNoChangeWindowHasNoFacts() throws {
        let trace = AccessibilityTrace.noChangeForTests(elementCount: 12)

        XCTAssertEqual(trace.captures.count, 2)
        XCTAssertTrue(trace.changeFacts.isEmpty)

        let data = try encoder.encode(trace)
        let json = try JSONProbe(data: data)
        try json.assertPresent("captures")
        try json.assertMissing("facts")
        try json.assertMissing("noChange")
    }

    // MARK: - Metadata

    func testTransientMetadataRoundTrip() throws {
        let spinner = makeElement(label: "Loading")
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init(
            metadata: .init(transient: [spinner])
        ))

        let decoded = try roundTrip(fact)

        XCTAssertEqual(decoded.metadata.transient.map(\.label), ["Loading"])
    }

    func testInteractionDigestRoundTripsOnFactMetadata() throws {
        let digest = AccessibilityTrace.InteractionDigest(
            nodeCountBefore: 1,
            nodeCountAfter: 2,
            elementSetChanged: true,
            screenIdBefore: "menu",
            screenIdAfter: "menu",
            firstResponderChanged: false
        )
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init(
            metadata: .init(interactionDigest: digest)
        ))

        let data = try encoder.encode(fact)
        let metadata = try JSONProbe(data: data).object("metadata")
        let digestJSON = try metadata.object("interactionDigest")
        XCTAssertEqual(try digestJSON.int("nodeCountBefore"), 1)
        XCTAssertEqual(try digestJSON.int("nodeCountAfter"), 2)
        XCTAssertEqual(try digestJSON.bool("nodeCountChanged"), true)
        XCTAssertEqual(try digestJSON.bool("elementSetChanged"), true)

        XCTAssertEqual(try roundTrip(fact).metadata.interactionDigest, digest)
    }

    func testCaptureEdgeRoundTripsInMetadata() throws {
        let edge = AccessibilityTrace.CaptureEdge(
            before: AccessibilityTrace.CaptureRef(sequence: 1, hash: "sha256:before"),
            after: AccessibilityTrace.CaptureRef(sequence: 2, hash: "sha256:after")
        )
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init(
            metadata: .init(captureEdge: edge)
        ))

        let data = try encoder.encode(fact)
        let edgeJSON = try JSONProbe(data: data).object("metadata").object("captureEdge")
        XCTAssertEqual(try edgeJSON.object("before").int("sequence"), 1)
        XCTAssertEqual(try edgeJSON.object("before").string("hash"), "sha256:before")
        XCTAssertEqual(try edgeJSON.object("after").int("sequence"), 2)
        XCTAssertEqual(try edgeJSON.object("after").string("hash"), "sha256:after")

        XCTAssertEqual(try roundTrip(fact).metadata.captureEdge, edge)
    }

    // MARK: - Elements changed

    func testElementsChangedSparseRoundTrip() throws {
        let appeared = makeNode(label: "Save")
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init(appeared: [appeared]))
        let data = try encoder.encode(fact)
        let json = try JSONProbe(data: data)

        XCTAssertEqual(try json.string("kind"), "elementsChanged")
        try json.assertPresent("appeared")
        try json.assertPresent("metadata")
        try json.assertMissing("disappeared")
        try json.assertMissing("updated")
        try json.assertMissing("elementCount")
        try json.assertMissing("edits")

        guard case .elementsChanged(let payload) = try roundTrip(fact) else {
            return XCTFail("Expected elementsChanged fact")
        }
        XCTAssertEqual(payload.appeared, [appeared])
        XCTAssertTrue(payload.disappeared.isEmpty)
        XCTAssertTrue(payload.updated.isEmpty)
    }

    func testElementsChangedEmptyArraysAreOmitted() throws {
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init())
        let data = try encoder.encode(fact)
        let json = try JSONProbe(data: data)

        try json.assertMissing("appeared")
        try json.assertMissing("disappeared")
        try json.assertMissing("updated")

        guard case .elementsChanged(let payload) = try roundTrip(fact) else {
            return XCTFail("Expected elementsChanged fact")
        }
        XCTAssertFalse(payload.hasLifecycleOrUpdateFacts)
    }

    func testElementsChangedFullRoundTrip() throws {
        let appeared = makeNode(label: "New")
        let disappeared = makeNode(label: "Old")
        let update = ElementUpdate(
            before: makeElement(label: "Counter", value: "1"),
            after: makeElement(label: "Counter", value: "2"),
            changes: [try XCTUnwrap(PropertyChange.value(old: "1", new: "2"))]
        )
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init(
            appeared: [appeared],
            disappeared: [disappeared],
            updated: [update],
            metadata: .init(transient: [makeElement(label: "Loading")])
        ))
        let data = try encoder.encode(fact)
        let json = try JSONProbe(data: data)
        let disappearedJSON = try json.array("disappeared")
        let disappearedNode = try XCTUnwrap(disappearedJSON.first)
        XCTAssertEqual(try disappearedNode.string("kind"), "element")
        try disappearedNode.assertMissing("heistId")
        let updatedJSON = try XCTUnwrap(try json.array("updated").first)
        try updatedJSON.assertMissing("element")
        XCTAssertEqual(try updatedJSON.object("before").string("value"), "1")
        XCTAssertEqual(try updatedJSON.object("after").string("value"), "2")
        let changeJSON = try XCTUnwrap(try updatedJSON.array("changes").first)
        XCTAssertEqual(try changeJSON.string("old"), "1")
        XCTAssertEqual(try changeJSON.string("new"), "2")

        guard case .elementsChanged(let payload) = try roundTrip(fact) else {
            return XCTFail("Expected elementsChanged fact")
        }
        XCTAssertEqual(payload.appeared, [appeared])
        XCTAssertEqual(payload.disappeared, [disappeared])
        XCTAssertEqual(payload.updated, [update])
        XCTAssertEqual(payload.metadata.transient.map(\.label), ["Loading"])
    }

    // MARK: - Screen changed

    func testScreenChangedRoundTripHasNoInterfacePayload() throws {
        let fact = AccessibilityTrace.ChangeFact.screenChanged(.init())
        let data = try encoder.encode(fact)
        let json = try JSONProbe(data: data)

        XCTAssertEqual(try json.string("kind"), "screenChanged")
        try json.assertPresent("metadata")
        try json.assertMissing("replacementInterface")
        try json.assertMissing("newInterface")
        try json.assertMissing("elementCount")

        XCTAssertEqual(try roundTrip(fact), fact)
    }

    func testScreenChangedMetadataRoundTrip() throws {
        let fact = AccessibilityTrace.ChangeFact.screenChanged(.init(
            metadata: .init(transient: [makeElement(label: "Loading")])
        ))

        guard case .screenChanged(let payload) = try roundTrip(fact) else {
            return XCTFail("Expected screenChanged fact")
        }
        XCTAssertEqual(payload.metadata.transient.map(\.label), ["Loading"])
    }

    // MARK: - Malformed input

    func testRejectsUnknownKind() {
        assertDecodeFailure(
            AccessibilityTrace.ChangeFact.self,
            json: #"{"kind":"shrugChanged","metadata":{}}"#,
            decoder: decoder
        )
    }

    func testRejectsMissingKind() {
        assertDecodeFailure(
            AccessibilityTrace.ChangeFact.self,
            json: #"{"metadata":{}}"#,
            decoder: decoder
        )
    }

    func testRejectsNoChangeFact() {
        assertDecodeFailure(
            AccessibilityTrace.ChangeFact.self,
            json: #"{"kind":"noChange","metadata":{}}"#,
            decoder: decoder
        )
    }

    func testRejectsMissingMetadata() {
        assertDecodeFailure(
            AccessibilityTrace.ChangeFact.self,
            json: #"{"kind":"elementsChanged"}"#,
            decoder: decoder
        )
    }

    func testRejectsScreenChangedElementPayloads() {
        assertDecodeFailure(
            AccessibilityTrace.ChangeFact.self,
            json: #"{"kind":"screenChanged","metadata":{},"appeared":[]}"#,
            decoder: decoder
        )
    }

    func testRejectsObsoleteScreenInterfacePayload() {
        assertDecodeFailure(
            AccessibilityTrace.ChangeFact.self,
            json: #"{"kind":"screenChanged","metadata":{},"replacementInterface":{}}"#,
            decoder: decoder
        )
    }

    // MARK: - PropertyChange

    func testPropertyChangeRejectsMismatchedTypedValues() throws {
        let json = Data(#"{"property":"traits","old":"button","new":["button","selected"]}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(PropertyChange.self, from: json))
    }

    func testPropertyChangeRejectsErasedElementPropertyValuePayloads() throws {
        let json = Data("""
        {
          "property": "value",
          "old": {"kind":"text","value":"1"},
          "new": {"kind":"text","value":"2"}
        }
        """.utf8)
        XCTAssertThrowsError(try decoder.decode(PropertyChange.self, from: json))
    }

    func testPropertyChangeRejectsNoOpTransition() throws {
        let json = Data(#"{"property":"value","old":"Ready","new":"Ready"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(PropertyChange.self, from: json))
    }

    func testPropertyChangeRejectsEmptyTransition() throws {
        let json = Data(#"{"property":"value"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(PropertyChange.self, from: json))
    }

    // MARK: - ElementEdits

    func testEmptyElementEditsEncodesEmptyObject() throws {
        let data = try encoder.encode(ElementEdits())
        XCTAssertTrue(try JSONProbe(data: data).isEmptyObject())
    }

    func testElementEditsRoundTripDropsEmptyArrays() throws {
        let edits = ElementEdits(added: [makeElement(label: "X")])
        let data = try encoder.encode(edits)
        let json = try JSONProbe(data: data)
        try json.assertPresent("added")
        try json.assertMissing("removed")
        try json.assertMissing("updated")

        let decoded = try decoder.decode(ElementEdits.self, from: data)
        XCTAssertEqual(decoded.added.map(\.label), ["X"])
        XCTAssertTrue(decoded.removed.isEmpty)
    }

    // MARK: - Helpers

    private func roundTrip(_ fact: AccessibilityTrace.ChangeFact) throws -> AccessibilityTrace.ChangeFact {
        try decoder.decode(AccessibilityTrace.ChangeFact.self, from: encoder.encode(fact))
    }

    private func makeNode(label: String) -> AccessibilityTrace.InterfaceChangeNode {
        let interface = makeTestInterface(elements: [makeElement(label: label)])
        guard let record = interface.graph.nodesInPathOrder.first else {
            preconditionFailure("test interface requires one node")
        }
        return AccessibilityTrace.InterfaceChangeNode(record: record)
    }

    private func makeElement(label: String, value: String? = nil) -> HeistElement {
        makeTestHeistElement(label: label, value: value, traits: [.button])
    }
}
