import XCTest
import AccessibilitySnapshotModel
@testable import TheScore

// MARK: - AccessibilityTrace.Delta Round-Trip Tests

/// Wire-shape gate for the new enum-of-cases AccessibilityTrace.Delta. Each case
/// covers a sparse and a full encoding plus a malformed-input rejection.
final class AccessibilityTraceDeltaRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - noChange

    func testNoChangeSparseRoundTrip() throws {
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 12))
        let data = try encoder.encode(delta)
        let json = try JSONProbe(data: data)
        XCTAssertEqual(try json.string("kind"), "noChange")
        XCTAssertEqual(try json.int("elementCount"), 12)
        try json.assertMissing("transient")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 12)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testNoChangeWithTransientsRoundTrip() throws {
        let spinner = makeElement(label: "Loading")
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 4, transient: [spinner]))
        let data = try encoder.encode(delta)
        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 4)
        XCTAssertEqual(payload.transient.map(\.label), ["Loading"])
    }

    func testInteractionDigestRoundTripsOnDeltaPayload() throws {
        let digest = AccessibilityTrace.InteractionDigest(
            elementCountBefore: 1,
            elementCountAfter: 2,
            elementSetChanged: true,
            screenIdBefore: "menu",
            screenIdAfter: "menu",
            firstResponderChanged: false
        )
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(
            elementCount: 2,
            edits: ElementEdits(added: [makeElement(label: "Bagel")]),
            interactionDigest: digest
        ))

        let data = try encoder.encode(delta)
        let json = try JSONProbe(data: data)
        let digestJSON = try json.object("interactionDigest")
        XCTAssertEqual(try digestJSON.int("elementCountBefore"), 1)
        XCTAssertEqual(try digestJSON.int("elementCountAfter"), 2)
        XCTAssertEqual(try digestJSON.bool("elementCountChanged"), true)
        XCTAssertEqual(try digestJSON.bool("elementSetChanged"), true)

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.interactionDigest, digest)
    }

    func testCaptureEdgeRoundTrips() throws {
        let edge = AccessibilityTrace.CaptureEdge(
            before: AccessibilityTrace.CaptureRef(sequence: 1, hash: "sha256:before"),
            after: AccessibilityTrace.CaptureRef(sequence: 2, hash: "sha256:after")
        )
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 4, captureEdge: edge))
        let data = try encoder.encode(delta)
        let edgeJson = try JSONProbe(data: data).object("captureEdge")
        let beforeJson = try edgeJson.object("before")
        let afterJson = try edgeJson.object("after")
        XCTAssertEqual(try beforeJson.int("sequence"), 1)
        XCTAssertEqual(try beforeJson.string("hash"), "sha256:before")
        XCTAssertEqual(try afterJson.int("sequence"), 2)
        XCTAssertEqual(try afterJson.string("hash"), "sha256:after")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.captureEdge, edge)
    }

    // MARK: - elementsChanged

    func testElementsChangedSparseRoundTrip() throws {
        let added = makeElement(label: "Save")
        let edits = ElementEdits(added: [added])
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 14, edits: edits))
        let data = try encoder.encode(delta)
        let json = try JSONProbe(data: data)
        XCTAssertEqual(try json.string("kind"), "elementsChanged")
        XCTAssertEqual(try json.int("elementCount"), 14)
        // edits live nested under "edits" — never flat at the top level.
        try json.assertMissing("added")
        try json.assertMissing("removed")
        try json.assertMissing("updated")
        try json.assertMissing("treeInserted")
        try json.assertMissing("transient")
        let editsJson = try json.object("edits")
        try editsJson.assertPresent("added")
        try editsJson.assertMissing("removed")
        try editsJson.assertMissing("updated")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 14)
        XCTAssertEqual(payload.edits.added.map(\.label), ["Save"])
        XCTAssertTrue(payload.edits.removed.isEmpty)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testElementsChangedEmptyEditsOmitsKey() throws {
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 3, edits: ElementEdits()))
        let data = try encoder.encode(delta)
        try JSONProbe(data: data).assertMissing("edits")

        // Missing edits key must decode as an empty ElementEdits.
        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertTrue(payload.edits.isEmpty)
    }

    func testElementsChangedFullRoundTrip() throws {
        let added = makeElement(label: "New")
        let removed = makeElement(label: "Old")
        let transient = makeElement(label: "Loading")
        let edits = ElementEdits(
            added: [added],
            removed: [removed],
            updated: [ElementUpdate(
                before: makeElement(label: "Counter", value: "1"),
                after: makeElement(label: "Counter", value: "2"),
                changes: [PropertyChange(property: .value, old: "1", new: "2")]
            )]
        )
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(
            elementCount: 14, edits: edits, transient: [transient]
        ))
        let data = try encoder.encode(delta)

        // heistId is excluded from the wire — the delta is self-describing by label.
        let editsJSON = try JSONProbe(data: data).object("edits")
        let removedJSON = try editsJSON.array("removed")
        XCTAssertEqual(removedJSON.count, 1)
        let removedElementJSON = try XCTUnwrap(removedJSON.first)
        XCTAssertEqual(try removedElementJSON.string("label"), "Old")
        try removedElementJSON.assertMissing("heistId")
        let updatedJSON = try editsJSON.array("updated")
        XCTAssertEqual(updatedJSON.count, 1)
        let updatedElementJSON = try XCTUnwrap(updatedJSON.first)
        try updatedElementJSON.assertMissing("element")
        XCTAssertEqual(try updatedElementJSON.object("before").string("value"), "1")
        XCTAssertEqual(try updatedElementJSON.object("after").string("value"), "2")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 14)
        XCTAssertEqual(payload.edits.added.map(\.label), ["New"])
        XCTAssertEqual(payload.edits.removed.map(\.label), ["Old"])
        XCTAssertEqual(payload.edits.updated.count, 1)
        let updatedEdit = try XCTUnwrap(payload.edits.updated.first)
        XCTAssertEqual(updatedEdit.after.label, "Counter")
        XCTAssertEqual(payload.transient.map(\.label), ["Loading"])
    }

    func testElementEditsRejectsObsoleteTreeProjectionFields() throws {
        let json = Data("""
        {"kind":"elementsChanged","elementCount":1,"edits":{"treeInserted":[]}}
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(AccessibilityTrace.Delta.self, from: json))
    }

    // MARK: - screenChanged

    func testScreenChangedCleanRoundTrip() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let delta = AccessibilityTrace.Delta.screenChanged(.init(
            elementCount: 8, newInterface: interface
        ))
        let data = try encoder.encode(delta)
        let json = try JSONProbe(data: data)
        XCTAssertEqual(try json.string("kind"), "screenChanged")
        XCTAssertEqual(try json.int("elementCount"), 8)
        try json.assertPresent("newInterface")
        try json.assertMissing("postEdits")
        try json.assertMissing("transient")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .screenChanged(let payload) = decoded else {
            return XCTFail("Expected .screenChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 8)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testScreenChangedWithTransientRoundTrip() throws {
        let transient = makeElement(label: "Loading")
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let delta = AccessibilityTrace.Delta.screenChanged(.init(
            elementCount: 9,
            newInterface: interface,
            transient: [transient]
        ))
        let data = try encoder.encode(delta)
        try JSONProbe(data: data).assertPresent("transient")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .screenChanged(let payload) = decoded else {
            return XCTFail("Expected .screenChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.transient.map(\.label), ["Loading"])
    }

    // MARK: - Malformed Input Rejection

    func testRejectsUnknownKind() {
        assertDecodeFailure(
            AccessibilityTrace.Delta.self,
            json: #"{"kind": "shrugChanged", "elementCount": 0}"#,
            decoder: decoder
        )
    }

    func testRejectsMissingKind() {
        assertDecodeFailure(
            AccessibilityTrace.Delta.self,
            json: #"{"elementCount": 0}"#,
            decoder: decoder
        )
    }

    func testRejectsScreenChangedWithoutNewInterface() {
        assertDecodeFailure(
            AccessibilityTrace.Delta.self,
            json: #"{"kind": "screenChanged", "elementCount": 0}"#,
            decoder: decoder
        )
    }

    func testRejectsMissingElementCount() {
        assertDecodeFailure(
            AccessibilityTrace.Delta.self,
            json: #"{"kind": "noChange"}"#,
            decoder: decoder
        )
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

    private func makeElement(label: String, value: String? = nil) -> HeistElement {
        makeTestHeistElement(
            label: label,
            value: value,
            traits: [.button]
        )
    }
}
