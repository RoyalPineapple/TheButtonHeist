import XCTest
import ThePlans
@testable import TheScore

final class HeistElementTests: XCTestCase {
    func testNestedElementContractRoundTrips() throws {
        let element = makeElement()

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let semantics = try XCTUnwrap(object["semantics"] as? [String: Any])
        let geometry = try XCTUnwrap(object["geometry"] as? [String: Any])
        let view = try XCTUnwrap(geometry["view"] as? [String: Any])

        XCTAssertEqual(decoded, element)
        XCTAssertEqual(Set(object.keys), ["semantics", "geometry"])
        XCTAssertEqual(
            Set(semantics.keys),
            ["spokenDescription", "assertable", "respondsToUserInteraction"]
        )
        XCTAssertEqual(Set(geometry.keys), ["screen", "view"])
        XCTAssertEqual(
            Set(view.keys),
            ["availability", "ownerPath", "frame", "activationPoint"]
        )
        XCTAssertEqual(view["availability"] as? String, "available")
        XCTAssertNil(object["description"])
        XCTAssertNil(geometry["scrollContent"])
        XCTAssertNil(view["containerPath"])
    }

    func testGeometryRequiresScreenAndView() {
        let semantics = canonicalSemanticsJSON
        let missingScreen = """
        {"semantics":\(semantics),"geometry":{"view":\(canonicalViewJSON)}}
        """
        let missingView = """
        {"semantics":\(semantics),"geometry":{"screen":\(canonicalScreenJSON)}}
        """

        XCTAssertThrowsError(try decode(missingScreen))
        XCTAssertThrowsError(try decode(missingView))
    }

    func testStrictContractRejectsUnknownKeysAtEveryElementLayer() {
        let unknownOuterKey = """
        {
          "semantics": \(canonicalSemanticsJSON),
          "geometry": {
            "screen": \(canonicalScreenJSON),
            "view": \(canonicalViewJSON)
          },
          "unexpected": true
        }
        """
        let unknownGeometryKey = """
        {
          "semantics": \(canonicalSemanticsJSON),
          "geometry": {
            "screen": \(canonicalScreenJSON),
            "view": \(canonicalViewJSON),
            "unexpected": true
          }
        }
        """
        let unknownViewKey = """
        {
          "semantics": \(canonicalSemanticsJSON),
          "geometry": {
            "screen": \(canonicalScreenJSON),
            "view": {
              "availability": "invalidated",
              "ownerPath": {"indices": []},
              "unexpected": true
            }
          }
        }
        """

        XCTAssertThrowsError(try decode(unknownOuterKey))
        XCTAssertThrowsError(try decode(unknownGeometryKey))
        XCTAssertThrowsError(try decode(unknownViewKey))
    }

    func testSemanticsEqualityAndHashAreIndependentFromGeometry() {
        let element = makeElement()
        let moved = HeistElement(
            semantics: element.semantics,
            geometry: shiftedGeometry(from: element.geometry)
        )

        XCTAssertEqual(element.semantics, moved.semantics)
        XCTAssertEqual(Set([element.semantics, moved.semantics]).count, 1)
        XCTAssertNotEqual(element.geometry, moved.geometry)
        XCTAssertNotEqual(element, moved)
        XCTAssertEqual(Set([element, moved]).count, 2)
    }

    func testScreenSpaceEqualityAndHashAreIndependentFromViewSpace() {
        let geometry = makeElement().geometry
        let available = requireAvailable(geometry.view)
        let changedView = HeistElement.Geometry(
            screen: geometry.screen,
            view: .available(.init(
                ownerPath: TreePath([1]),
                frame: available.frame,
                activationPoint: available.activationPoint
            ))
        )

        XCTAssertEqual(geometry.screen, changedView.screen)
        XCTAssertEqual(Set([geometry.screen, changedView.screen]).count, 1)
        XCTAssertNotEqual(geometry.view, changedView.view)
        XCTAssertNotEqual(geometry, changedView)
        XCTAssertEqual(Set([geometry, changedView]).count, 2)
    }

    func testViewSpaceEqualityAndHashAreIndependentFromScreenSpace() {
        let geometry = makeElement().geometry
        let changedScreen = HeistElement.Geometry(
            screen: .offscreen,
            view: geometry.view
        )

        XCTAssertEqual(geometry.view, changedScreen.view)
        XCTAssertEqual(Set([geometry.view, changedScreen.view]).count, 1)
        XCTAssertNotEqual(geometry.screen, changedScreen.screen)
        XCTAssertNotEqual(geometry, changedScreen)
        XCTAssertEqual(Set([geometry, changedScreen]).count, 2)
    }

    func testViewSpaceAdmissionRequiresCompletePair() {
        let ownerPath = TreePath([2])
        let frame = ViewRect(x: 10, y: 20, width: 100, height: 44)
        let activationPoint = ViewPoint(x: 60, y: 42)
        let available = HeistElement.Geometry.ViewSpace.available(.init(
            ownerPath: ownerPath,
            frame: frame,
            activationPoint: activationPoint
        ))
        let invalidated = HeistElement.Geometry.ViewSpace.invalidated(ownerPath: ownerPath)

        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace.admit(
                ownerPath: ownerPath,
                frame: frame,
                activationPoint: activationPoint
            ),
            available
        )
        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace.admit(
                ownerPath: ownerPath,
                frame: frame,
                activationPoint: nil
            ),
            invalidated
        )
        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace.admit(
                ownerPath: ownerPath,
                frame: nil,
                activationPoint: activationPoint
            ),
            invalidated
        )
        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace.admit(
                ownerPath: ownerPath,
                frame: nil,
                activationPoint: nil
            ),
            invalidated
        )
    }

    func testAvailableViewSpaceRoundTripsWithSingularWireShape() throws {
        let viewSpace = HeistElement.Geometry.ViewSpace.available(.init(
            ownerPath: TreePath([2, 1]),
            frame: ViewRect(x: 10, y: 20, width: 100, height: 44),
            activationPoint: ViewPoint(x: 60, y: 42)
        ))

        let data = try JSONEncoder().encode(viewSpace)
        let decoded = try JSONDecoder().decode(
            HeistElement.Geometry.ViewSpace.self,
            from: data
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, viewSpace)
        XCTAssertEqual(
            Set(object.keys),
            ["availability", "ownerPath", "frame", "activationPoint"]
        )
        XCTAssertEqual(object["availability"] as? String, "available")
    }

    func testInvalidatedViewSpaceRoundTripsWithoutGeometryKeys() throws {
        let viewSpace = HeistElement.Geometry.ViewSpace.invalidated(
            ownerPath: TreePath([3])
        )

        let data = try JSONEncoder().encode(viewSpace)
        let decoded = try JSONDecoder().decode(
            HeistElement.Geometry.ViewSpace.self,
            from: data
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, viewSpace)
        XCTAssertEqual(Set(object.keys), ["availability", "ownerPath"])
        XCTAssertEqual(object["availability"] as? String, "invalidated")
    }

    func testViewSpaceDecodingRejectsHistoricalAndPartialShapes() {
        let rejectedJSON = [
            """
            {"ownerPath":{"indices":[]},"frame":\(canonicalViewFrameJSON),"activationPoint":\(canonicalViewPointJSON)}
            """,
            """
            {"ownerPath":{"indices":[]},"frame":\(canonicalViewFrameJSON)}
            """,
            """
            {"ownerPath":{"indices":[]},"activationPoint":\(canonicalViewPointJSON)}
            """,
            """
            {"ownerPath":{"indices":[]}}
            """,
            """
            {"ownerPath":{"indices":[]},"frame":null,"activationPoint":null}
            """,
            """
            {"availability":"unknown","ownerPath":{"indices":[]}}
            """,
            """
            {"availability":"available","frame":\(canonicalViewFrameJSON),"activationPoint":\(canonicalViewPointJSON)}
            """,
            """
            {"availability":"available","ownerPath":{"indices":[]},"activationPoint":\(canonicalViewPointJSON)}
            """,
            """
            {"availability":"available","ownerPath":{"indices":[]},"frame":\(canonicalViewFrameJSON)}
            """,
            """
            {"availability":"available","ownerPath":{"indices":[]},"frame":null,"activationPoint":\(canonicalViewPointJSON)}
            """,
            """
            {"availability":"available","ownerPath":{"indices":[]},"frame":\(canonicalViewFrameJSON),"activationPoint":null}
            """,
            """
            {
              "availability":"available",
              "ownerPath":{"indices":[]},
              "frame":\(canonicalViewFrameJSON),
              "activationPoint":\(canonicalViewPointJSON),
              "unexpected":true
            }
            """,
            """
            {"availability":"invalidated","ownerPath":{"indices":[]},"frame":\(canonicalViewFrameJSON)}
            """,
            """
            {"availability":"invalidated","ownerPath":{"indices":[]},"activationPoint":\(canonicalViewPointJSON)}
            """,
        ]

        for json in rejectedJSON {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    HeistElement.Geometry.ViewSpace.self,
                    from: Data(json.utf8)
                ),
                "Unexpectedly decoded \(json)"
            )
        }
    }

    func testViewSpaceOwnerQualificationRetainsOnlyMatchingAvailability() {
        let expectedOwner = TreePath([2])
        let otherOwner = TreePath([3])
        let available = HeistElement.Geometry.ViewSpace.available(.init(
            ownerPath: expectedOwner,
            frame: ViewRect(x: 10, y: 20, width: 100, height: 44),
            activationPoint: ViewPoint(x: 60, y: 42)
        ))
        let invalidated = HeistElement.Geometry.ViewSpace.invalidated(
            ownerPath: expectedOwner
        )

        XCTAssertEqual(available.admitted(ownedBy: expectedOwner), available)
        XCTAssertEqual(invalidated.admitted(ownedBy: expectedOwner), invalidated)
        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace
                .invalidated(ownerPath: otherOwner)
                .admitted(ownedBy: expectedOwner),
            invalidated,
            "Missing or ambiguous ownership must remain invalidated for the expected owner"
        )
        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace
                .available(.init(
                    ownerPath: otherOwner,
                    frame: ViewRect(x: 10, y: 20, width: 100, height: 44),
                    activationPoint: ViewPoint(x: 60, y: 42)
                ))
                .admitted(ownedBy: expectedOwner),
            invalidated,
            "A nonmatching owner must not donate geometry"
        )
    }

    func testViewSpaceRebasePreservesCaseAndPairedGeometry() {
        let originalRoot = TreePath([2])
        let projectedRoot = TreePath([7])
        let originalOwner = TreePath([2, 4])
        let projectedOwner = TreePath([7, 4])
        let frame = ViewRect(x: 10, y: 20, width: 100, height: 44)
        let activationPoint = ViewPoint(x: 60, y: 42)

        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace
                .available(.init(
                    ownerPath: originalOwner,
                    frame: frame,
                    activationPoint: activationPoint
                ))
                .rebased(fromSubtreeRoot: originalRoot, to: projectedRoot),
            .available(.init(
                ownerPath: projectedOwner,
                frame: frame,
                activationPoint: activationPoint
            ))
        )
        XCTAssertEqual(
            HeistElement.Geometry.ViewSpace
                .invalidated(ownerPath: originalOwner)
                .rebased(fromSubtreeRoot: originalRoot, to: projectedRoot),
            .invalidated(ownerPath: projectedOwner)
        )
    }

    func testAssertableCollectionsEncodeDeterministically() throws {
        let element = makeElement()
        let encoded = try JSONEncoder().encode(element)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let semantics = try XCTUnwrap(object["semantics"] as? [String: Any])
        let assertable = try XCTUnwrap(semantics["assertable"] as? [String: Any])
        let actions = try XCTUnwrap(assertable["actions"] as? [Any])
        let customAction = try XCTUnwrap(actions[1] as? [String: String])

        XCTAssertEqual(assertable["traits"] as? [String], ["button", "header"])
        XCTAssertEqual(actions[0] as? String, "activate")
        XCTAssertEqual(customAction, ["custom": "Delete"])
    }

    private var canonicalSemanticsJSON: String {
        """
        {
          "spokenDescription": "Save. Button.",
          "assertable": {
            "label": "Save",
            "traits": ["button"],
            "customContent": [],
            "rotors": [],
            "actions": ["activate"]
          },
          "respondsToUserInteraction": true
        }
        """
    }

    private var canonicalScreenJSON: String {
        """
        {
          "visibility": "onscreen",
          "frame": {
            "availability": "available",
            "rect": {"x": 10, "y": 20, "width": 100, "height": 44}
          },
          "activationPoint": {
            "source": "explicit",
            "point": {"x": 60, "y": 42}
          }
        }
        """
    }

    private var canonicalViewJSON: String {
        """
        {
          "availability": "available",
          "ownerPath": {"indices": []},
          "frame": \(canonicalViewFrameJSON),
          "activationPoint": \(canonicalViewPointJSON)
        }
        """
    }

    private var canonicalViewFrameJSON: String {
        #"{"x":10,"y":20,"width":100,"height":44}"#
    }

    private var canonicalViewPointJSON: String {
        #"{"x":60,"y":42}"#
    }

    private func decode(_ json: String) throws -> HeistElement {
        try JSONDecoder().decode(HeistElement.self, from: Data(json.utf8))
    }

    private func makeElement() -> HeistElement {
        HeistElement(
            semantics: .init(
                spokenDescription: "Save. Button.",
                assertable: .init(
                    label: "Save",
                    value: nil,
                    identifier: "save",
                    hint: "Saves changes",
                    traits: [.header, .button],
                    customContent: [
                        .init(label: "Status", value: "Ready", isImportant: true),
                    ],
                    rotors: [.init(name: "Actions")],
                    actions: [.custom("Delete"), .activate]
                ),
                respondsToUserInteraction: true
            ),
            geometry: .init(
                screen: .onscreen(
                    frame: .available(ScreenRect(
                        x: 10,
                        y: 20,
                        width: 100,
                        height: 44
                    )),
                    activationPoint: .explicit(ScreenPoint(x: 60, y: 42))
                ),
                view: .available(.init(
                    ownerPath: .root,
                    frame: ViewRect(
                        x: 10,
                        y: 20,
                        width: 100,
                        height: 44
                    ),
                    activationPoint: ViewPoint(x: 60, y: 42)
                ))
            )
        )
    }

    private func shiftedGeometry(
        from geometry: HeistElement.Geometry
    ) -> HeistElement.Geometry {
        let available = requireAvailable(geometry.view)
        return .init(
            screen: .onscreen(
                frame: .available(ScreenRect(
                    x: 30,
                    y: 40,
                    width: 100,
                    height: 44
                )),
                activationPoint: .explicit(ScreenPoint(x: 80, y: 62))
            ),
            view: .available(.init(
                ownerPath: TreePath([1]),
                frame: available.frame,
                activationPoint: available.activationPoint
            ))
        )
    }

    private func requireAvailable(
        _ viewSpace: HeistElement.Geometry.ViewSpace
    ) -> HeistElement.Geometry.ViewSpace.Available {
        guard case .available(let available) = viewSpace else {
            preconditionFailure("Expected available parent-space geometry")
        }
        return available
    }
}
