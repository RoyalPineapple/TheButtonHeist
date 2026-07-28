import XCTest
import ThePlans
import TheScore

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
        XCTAssertEqual(Set(view.keys), ["ownerPath", "frame", "activationPoint"])
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
              "ownerPath": [],
              "frame": null,
              "activationPoint": null,
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
        let changedView = HeistElement.Geometry(
            screen: geometry.screen,
            view: .init(
                ownerPath: TreePath([1]),
                frame: geometry.view.frame,
                activationPoint: geometry.view.activationPoint
            )
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
          "ownerPath": [],
          "frame": {"x": 10, "y": 20, "width": 100, "height": 44},
          "activationPoint": {"x": 60, "y": 42}
        }
        """
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
                view: .init(
                    ownerPath: .root,
                    frame: ViewRect(
                        x: 10,
                        y: 20,
                        width: 100,
                        height: 44
                    ),
                    activationPoint: ViewPoint(x: 60, y: 42)
                )
            )
        )
    }

    private func shiftedGeometry(
        from geometry: HeistElement.Geometry
    ) -> HeistElement.Geometry {
        .init(
            screen: .onscreen(
                frame: .available(ScreenRect(
                    x: 30,
                    y: 40,
                    width: 100,
                    height: 44
                )),
                activationPoint: .explicit(ScreenPoint(x: 80, y: 62))
            ),
            view: .init(
                ownerPath: TreePath([1]),
                frame: geometry.view.frame,
                activationPoint: geometry.view.activationPoint
            )
        )
    }
}
