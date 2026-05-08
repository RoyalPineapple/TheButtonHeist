import XCTest
@testable import TheScore

// MARK: - InterfaceDelta Round-Trip Tests

/// Wire-shape gate for the new enum-of-cases InterfaceDelta. Each case
/// covers a sparse and a full encoding plus a malformed-input rejection.
final class InterfaceDeltaRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - noChange

    func testNoChangeSparseRoundTrip() throws {
        let delta = InterfaceDelta.noChange(.init(elementCount: 12))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "noChange")
        XCTAssertEqual(json["elementCount"] as? Int, 12)
        XCTAssertNil(json["transient"])

        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 12)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testNoChangeWithTransientsRoundTrip() throws {
        let spinner = makeElement(heistId: "spin", label: "Loading")
        let delta = InterfaceDelta.noChange(.init(elementCount: 4, transient: [spinner]))
        let data = try encoder.encode(delta)
        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected .noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 4)
        XCTAssertEqual(payload.transient.map(\.heistId), ["spin"])
    }

    // MARK: - elementsChanged

    func testElementsChangedSparseRoundTrip() throws {
        let added = makeElement(heistId: "save", label: "Save")
        let edits = ElementEdits(added: [added])
        let delta = InterfaceDelta.elementsChanged(.init(elementCount: 14, edits: edits))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "elementsChanged")
        XCTAssertEqual(json["elementCount"] as? Int, 14)
        XCTAssertNotNil(json["added"])
        XCTAssertNil(json["removed"])
        XCTAssertNil(json["updated"])
        XCTAssertNil(json["treeInserted"])
        XCTAssertNil(json["transient"])

        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected .elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 14)
        XCTAssertEqual(payload.edits.added.map(\.heistId), ["save"])
        XCTAssertTrue(payload.edits.removed.isEmpty)
        XCTAssertTrue(payload.transient.isEmpty)
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
                node: .element(added)
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
        let delta = InterfaceDelta.elementsChanged(.init(
            elementCount: 14, edits: edits, transient: [transient]
        ))
        let data = try encoder.encode(delta)
        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
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
        let delta = InterfaceDelta.screenChanged(.init(
            elementCount: 8, newInterface: interface
        ))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "screenChanged")
        XCTAssertEqual(json["elementCount"] as? Int, 8)
        XCTAssertNotNil(json["newInterface"])
        XCTAssertNil(json["postEdits"])
        XCTAssertNil(json["transient"])

        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
        guard case .screenChanged(let payload) = decoded else {
            return XCTFail("Expected .screenChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.elementCount, 8)
        XCTAssertNil(payload.postEdits)
        XCTAssertTrue(payload.transient.isEmpty)
    }

    func testScreenChangedWithPostEditsRoundTrip() throws {
        let added = makeElement(heistId: "post", label: "Posted")
        let transient = makeElement(heistId: "spin", label: "Loading")
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let postEdits = ElementEdits(added: [added])
        let delta = InterfaceDelta.screenChanged(.init(
            elementCount: 9,
            newInterface: interface,
            postEdits: postEdits,
            transient: [transient]
        ))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["postEdits"])
        XCTAssertNotNil(json["transient"])

        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
        guard case .screenChanged(let payload) = decoded else {
            return XCTFail("Expected .screenChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.postEdits?.added.map(\.heistId), ["post"])
        XCTAssertEqual(payload.transient.map(\.heistId), ["spin"])
    }

    func testScreenChangedDropsEmptyPostEdits() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let delta = InterfaceDelta.screenChanged(.init(
            elementCount: 8,
            newInterface: interface,
            postEdits: ElementEdits()
        ))
        let data = try encoder.encode(delta)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["postEdits"], "postEdits should be omitted when empty")
    }

    // MARK: - Cross-Case Accessors

    func testElementCountAccessor() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        XCTAssertEqual(InterfaceDelta.noChange(.init(elementCount: 4)).elementCount, 4)
        XCTAssertEqual(
            InterfaceDelta.elementsChanged(.init(elementCount: 7, edits: ElementEdits())).elementCount,
            7
        )
        XCTAssertEqual(
            InterfaceDelta.screenChanged(.init(elementCount: 9, newInterface: interface)).elementCount,
            9
        )
    }

    func testKindRawValueAccessor() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        XCTAssertEqual(InterfaceDelta.noChange(.init(elementCount: 0)).kindRawValue, "noChange")
        XCTAssertEqual(
            InterfaceDelta.elementsChanged(.init(elementCount: 0, edits: ElementEdits())).kindRawValue,
            "elementsChanged"
        )
        XCTAssertEqual(
            InterfaceDelta.screenChanged(.init(elementCount: 0, newInterface: interface)).kindRawValue,
            "screenChanged"
        )
    }

    func testIsScreenChangedAccessor() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        XCTAssertFalse(InterfaceDelta.noChange(.init(elementCount: 0)).isScreenChanged)
        XCTAssertFalse(
            InterfaceDelta.elementsChanged(.init(elementCount: 0, edits: ElementEdits())).isScreenChanged
        )
        XCTAssertTrue(
            InterfaceDelta.screenChanged(.init(elementCount: 0, newInterface: interface)).isScreenChanged
        )
    }

    func testElementEditsAccessorReadsBothCases() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 1_000_000), tree: [])
        let element = makeElement(heistId: "x", label: "X")
        let elementsChanged = InterfaceDelta.elementsChanged(
            .init(elementCount: 1, edits: ElementEdits(added: [element]))
        )
        XCTAssertEqual(elementsChanged.elementEdits?.added.map(\.heistId), ["x"])

        let screenChanged = InterfaceDelta.screenChanged(.init(
            elementCount: 1,
            newInterface: interface,
            postEdits: ElementEdits(added: [element])
        ))
        XCTAssertEqual(screenChanged.elementEdits?.added.map(\.heistId), ["x"])

        let screenChangedNoPostEdits = InterfaceDelta.screenChanged(.init(
            elementCount: 1, newInterface: interface
        ))
        XCTAssertNil(screenChangedNoPostEdits.elementEdits)

        let noChange = InterfaceDelta.noChange(.init(elementCount: 0))
        XCTAssertNil(noChange.elementEdits)
    }

    // MARK: - Malformed Input Rejection

    func testRejectsUnknownKind() {
        let payload = #"{"kind": "shrugChanged", "elementCount": 0}"#
        XCTAssertThrowsError(
            try decoder.decode(InterfaceDelta.self, from: Data(payload.utf8))
        )
    }

    func testRejectsMissingKind() {
        let payload = #"{"elementCount": 0}"#
        XCTAssertThrowsError(
            try decoder.decode(InterfaceDelta.self, from: Data(payload.utf8))
        )
    }

    func testRejectsScreenChangedWithoutNewInterface() {
        let payload = #"{"kind": "screenChanged", "elementCount": 0}"#
        XCTAssertThrowsError(
            try decoder.decode(InterfaceDelta.self, from: Data(payload.utf8))
        )
    }

    func testRejectsMissingElementCount() {
        let payload = #"{"kind": "noChange"}"#
        XCTAssertThrowsError(
            try decoder.decode(InterfaceDelta.self, from: Data(payload.utf8))
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

    private func makeElement(heistId: String, label: String) -> HeistElement {
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
