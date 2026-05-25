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
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "noChange")
        XCTAssertEqual(json["elementCount"] as? Int, 12)
        XCTAssertNil(json["transient"])

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 12)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testNoChangeWithTransientsRoundTrip() throws {
        let spinner = makeElement(heistId: "spin", label: "Loading")
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 4, transient: [spinner]))
        let data = try encoder.encode(delta)
        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 4)
        XCTAssertEqual(payload.transient.map(\.heistId), ["spin"])
    }

    func testCaptureEdgeRoundTrips() throws {
        let edge = AccessibilityTrace.CaptureEdge(
            before: AccessibilityTrace.CaptureRef(sequence: 1, hash: "sha256:before"),
            after: AccessibilityTrace.CaptureRef(sequence: 2, hash: "sha256:after")
        )
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 4, captureEdge: edge))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let edgeJson = try XCTUnwrap(json["captureEdge"] as? [String: Any])
        let beforeJson = try XCTUnwrap(edgeJson["before"] as? [String: Any])
        let afterJson = try XCTUnwrap(edgeJson["after"] as? [String: Any])
        XCTAssertEqual(beforeJson["sequence"] as? Int, 1)
        XCTAssertEqual(beforeJson["hash"] as? String, "sha256:before")
        XCTAssertEqual(afterJson["sequence"] as? Int, 2)
        XCTAssertEqual(afterJson["hash"] as? String, "sha256:after")

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        XCTAssertEqual(decoded.captureEdge, edge)
    }

    // MARK: - elementsChanged

    func testElementsChangedSparseRoundTrip() throws {
        let added = makeElement(heistId: "save", label: "Save")
        let edits = ElementEdits(added: [added])
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 14, edits: edits))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "elementsChanged")
        XCTAssertEqual(json["elementCount"] as? Int, 14)
        // edits live nested under "edits" — never flat at the top level.
        XCTAssertNil(json["added"])
        XCTAssertNil(json["removed"])
        XCTAssertNil(json["updated"])
        XCTAssertNil(json["treeInserted"])
        XCTAssertNil(json["transient"])
        let editsJson = try XCTUnwrap(json["edits"] as? [String: Any])
        XCTAssertNotNil(editsJson["added"])
        XCTAssertNil(editsJson["removed"])
        XCTAssertNil(editsJson["updated"])

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 14)
        XCTAssertEqual(payload.edits.added.map(\.heistId), ["save"])
        XCTAssertTrue(payload.edits.removed.isEmpty)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testElementsChangedEmptyEditsOmitsKey() throws {
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 3, edits: ElementEdits()))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["edits"], "edits should be omitted when empty")

        // Missing edits key must decode as an empty ElementEdits.
        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertTrue(payload.edits.isEmpty)
    }

    func testElementsChangedRejectsLegacyFlatShape() {
        // The current shape nests ElementEdits under `edits`; flat fields fail fast.
        let element = """
            {"heistId":"x","description":"X","label":"X","traits":["button"],\
            "frameX":0,"frameY":0,"frameWidth":0,"frameHeight":0,\
            "actions":["activate"]}
            """
        let payload = """
            {"kind":"elementsChanged","elementCount":1,"added":[\(element)]}
            """
        XCTAssertThrowsError(try decoder.decode(AccessibilityTrace.Delta.self, from: Data(payload.utf8))) { error in
            XCTAssertTrue(
                "\(error)".contains("added"),
                "Expected flat delta field in error, got \(error)"
            )
        }
    }

    func testElementsChangedFullRoundTrip() throws {
        let added = makeElement(heistId: "new", label: "New")
        let transient = makeElement(heistId: "spin", label: "Loading")
        let edits = ElementEdits(
            added: [added],
            removed: ["old"],
            updated: [ElementUpdate(
                heistId: "counter",
                changes: [PropertyChange(property: .value, old: "1", new: "2")]
            )],
            treeInserted: [TreeInsertion(
                location: TreeLocation(parentId: nil, index: 0),
                node: .element(makeTestAccessibilityElement(added), traversalIndex: 0)
            )],
            treeRemoved: [TreeRemoval(
                ref: TreeNodeRef(id: "old", kind: .element),
                location: TreeLocation(parentId: nil, index: 1)
            )],
            treeMoved: [TreeMove(
                ref: TreeNodeRef(id: "moved", kind: .element),
                from: TreeLocation(parentId: nil, index: 2),
                to: TreeLocation(parentId: nil, index: 3)
            )]
        )
        let delta = AccessibilityTrace.Delta.elementsChanged(.init(
            elementCount: 14, edits: edits, transient: [transient]
        ))
        let data = try encoder.encode(delta)
        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 14)
        XCTAssertEqual(payload.edits.added.map(\.heistId), ["new"])
        XCTAssertEqual(payload.edits.removed, ["old"])
        XCTAssertEqual(payload.edits.updated.first?.heistId, "counter")
        XCTAssertEqual(payload.edits.treeInserted.count, 1)
        XCTAssertEqual(payload.edits.treeRemoved.count, 1)
        XCTAssertEqual(payload.edits.treeMoved.count, 1)
        XCTAssertEqual(payload.transient.map(\.heistId), ["spin"])
    }

    // MARK: - screenChanged

    func testScreenChangedCleanRoundTrip() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let delta = AccessibilityTrace.Delta.screenChanged(.init(
            elementCount: 8, newInterface: interface
        ))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "screenChanged")
        XCTAssertEqual(json["elementCount"] as? Int, 8)
        XCTAssertNotNil(json["newInterface"])
        XCTAssertNil(json["postEdits"])
        XCTAssertNil(json["transient"])

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .screenChanged(let payload) = decoded else {
            return XCTFail("Expected .screenChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 8)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testScreenChangedWithTransientRoundTrip() throws {
        let transient = makeElement(heistId: "spin", label: "Loading")
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let delta = AccessibilityTrace.Delta.screenChanged(.init(
            elementCount: 9,
            newInterface: interface,
            transient: [transient]
        ))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["transient"])

        let decoded = try decoder.decode(AccessibilityTrace.Delta.self, from: data)
        guard case .screenChanged(let payload) = decoded else {
            return XCTFail("Expected .screenChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.transient.map(\.heistId), ["spin"])
    }

    func testScreenChangedRejectsLegacyInterfaceShape() {
        let json = """
        {
          "kind": "screenChanged",
          "elementCount": 1,
          "newInterface": { "timestamp": 1000000, "tree": [] },
          "postEdits": {
            "added": [{
              "heistId": "legacy",
              "description": "Legacy",
              "label": "Legacy",
              "traits": ["staticText"],
              "frameX": 0,
              "frameY": 0,
              "frameWidth": 10,
              "frameHeight": 10,
              "actions": []
            }]
          }
        }
        """
        XCTAssertThrowsError(
            try decoder.decode(AccessibilityTrace.Delta.self, from: Data(json.utf8)),
            "Legacy screenChanged payloads without interface annotations are no longer accepted"
        )
    }

    // MARK: - Cross-Case Accessors

    func testElementCountAccessor() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        XCTAssertEqual(AccessibilityTrace.Delta.noChange(.init(elementCount: 4)).elementCount, 4)
        XCTAssertEqual(
            AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 7, edits: ElementEdits())).elementCount,
            7
        )
        XCTAssertEqual(
            AccessibilityTrace.Delta.screenChanged(.init(elementCount: 9, newInterface: interface)).elementCount,
            9
        )
    }

    func testKindRawValueAccessor() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        XCTAssertEqual(AccessibilityTrace.Delta.noChange(.init(elementCount: 0)).kindRawValue, "noChange")
        XCTAssertEqual(
            AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 0, edits: ElementEdits())).kindRawValue,
            "elementsChanged"
        )
        XCTAssertEqual(
            AccessibilityTrace.Delta.screenChanged(.init(elementCount: 0, newInterface: interface)).kindRawValue,
            "screenChanged"
        )
    }

    func testIsScreenChangedAccessor() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        XCTAssertFalse(AccessibilityTrace.Delta.noChange(.init(elementCount: 0)).isScreenChanged)
        XCTAssertFalse(
            AccessibilityTrace.Delta.elementsChanged(.init(elementCount: 0, edits: ElementEdits())).isScreenChanged
        )
        XCTAssertTrue(
            AccessibilityTrace.Delta.screenChanged(.init(elementCount: 0, newInterface: interface)).isScreenChanged
        )
    }

    func testElementEditsAccessorReadsElementsChangedOnly() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let element = makeElement(heistId: "x", label: "X")
        let elementsChanged = AccessibilityTrace.Delta.elementsChanged(
            .init(elementCount: 1, edits: ElementEdits(added: [element]))
        )
        XCTAssertEqual(elementsChanged.elementEdits?.added.map(\.heistId), ["x"])

        let screenChanged = AccessibilityTrace.Delta.screenChanged(.init(
            elementCount: 1,
            newInterface: interface
        ))
        XCTAssertNil(screenChanged.elementEdits)

        let noChange = AccessibilityTrace.Delta.noChange(.init(elementCount: 0))
        XCTAssertNil(noChange.elementEdits)
    }

    // MARK: - Malformed Input Rejection

    func testRejectsUnknownKind() {
        let payload = #"{"kind": "shrugChanged", "elementCount": 0}"#
        XCTAssertThrowsError(
            try decoder.decode(AccessibilityTrace.Delta.self, from: Data(payload.utf8))
        )
    }

    func testRejectsMissingKind() {
        let payload = #"{"elementCount": 0}"#
        XCTAssertThrowsError(
            try decoder.decode(AccessibilityTrace.Delta.self, from: Data(payload.utf8))
        )
    }

    func testRejectsScreenChangedWithoutNewInterface() {
        let payload = #"{"kind": "screenChanged", "elementCount": 0}"#
        XCTAssertThrowsError(
            try decoder.decode(AccessibilityTrace.Delta.self, from: Data(payload.utf8))
        )
    }

    func testRejectsMissingElementCount() {
        let payload = #"{"kind": "noChange"}"#
        XCTAssertThrowsError(
            try decoder.decode(AccessibilityTrace.Delta.self, from: Data(payload.utf8))
        )
    }

    // MARK: - ElementEdits

    func testEmptyElementEditsEncodesEmptyObject() throws {
        let data = try encoder.encode(ElementEdits())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json.isEmpty)
    }

    func testElementEditsRoundTripDropsEmptyArrays() throws {
        let edits = ElementEdits(added: [makeElement(heistId: "x", label: "X")])
        let data = try encoder.encode(edits)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["added"])
        XCTAssertNil(json["removed"])
        XCTAssertNil(json["updated"])

        let decoded = try decoder.decode(ElementEdits.self, from: data)
        XCTAssertEqual(decoded.added.map(\.heistId), ["x"])
        XCTAssertTrue(decoded.removed.isEmpty)
    }

    // MARK: - Helpers

    private func makeElement(heistId: HeistId, label: String) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
    }
}
