import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class TheFenceCompactFormattingContractTests: XCTestCase {

    func assertHeistReportRootOmitsSummaryDuplicates(
        _ json: JSONProbe,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        do {
            try json.assertMissing("executedTopLevelStepCount")
            try json.assertMissing("executedNodeCount")
            try json.assertMissing("outputNodeCount")
            try json.assertMissing("durationMs")
            try json.assertMissing("abortedAtPath")
            try json.assertMissing("expectations")
            try json.assertMissing("netDelta")
        } catch {
            XCTFail("\(error)", file: file, line: line)
            throw error
        }
    }

    func formattingFixtureInterface() -> Interface {
        let submit = makeTestHeistElement(label: "Submit", traits: [.button], actions: [.activate])
        let orderId = makeTestHeistElement(label: "Order ID", traits: [.staticText])
        let home = makeTestHeistElement(label: "Home", traits: [.tabBarItem])
        let bottom = makeTestHeistElement(label: "Bottom", traits: [.staticText])

        return makeTestInterface(nodes: [
            .container(
                makeTestSemanticContainer(
                    label: "Actions",
                    identifier: "actions",
                    frameX: 0,
                    frameY: 40,
                    frameWidth: 200,
                    frameHeight: 100
                ),
                containerName: "semantic_actions__actions",
                children: [
                    .element(submit),
                    .container(
                        makeTestAccessibilityContainer(
                            type: .dataTable(rowCount: 3, columnCount: 4, cells: []),
                            frameX: 8,
                            frameY: 52,
                            frameWidth: 180,
                            frameHeight: 36
                        ),
                        containerName: "orders_table",
                        children: [.element(orderId)]
                    ),
                    .container(
                        makeTestAccessibilityContainer(
                            type: .tabBar,
                            frameX: 0,
                            frameY: 140,
                            frameWidth: 200,
                            frameHeight: 44
                        ),
                        containerName: "main_tabs",
                        children: [.element(home)]
                    ),
                ]
            ),
            .container(
                makeTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1200,
                    frameX: 0,
                    frameY: 220,
                    frameWidth: 390,
                    frameHeight: 400,
                    isModalBoundary: true
                ),
                containerName: "main_scroll",
                children: [.element(bottom)]
            ),
        ])
    }

    func testCompactScreenshotIncludeInterfaceTextRules() {
        let interface = formattingFixtureInterface()
        let payload = ScreenPayload(pngData: "abc", width: 100, height: 200, interface: interface)

        XCTAssertEqual(
            FenceResponse.screenshotData(payload: payload, options: .init(includeInterface: false)).compactFormatted(),
            "screenshot: 100x200"
        )

        let withInterface = FenceResponse.screenshotData(
            payload: payload,
            options: .init(includeInterface: true)
        ).compactFormatted()
        XCTAssertTrue(withInterface.hasPrefix("screenshot: 100x200\n4 elements\n"), withInterface)
        XCTAssertTrue(
            withInterface.contains(
                #"── group "Actions" id="actions" "semantic_actions__actions" frame=(0,40,200,100) ──"#
            ),
            withInterface
        )
        XCTAssertFalse(withInterface.contains("stableId"), withInterface)

        XCTAssertEqual(
            FenceResponse.screenshotData(
                payload: ScreenPayload(pngData: "abc", width: 100, height: 200, interface: nil),
                options: .init(includeInterface: true)
            ).compactFormatted(),
            "screenshot: 100x200\ninterface: unavailable"
        )
    }

    func testHumanScreenshotIncludeInterfaceUnavailable() {
        let output = FenceResponse.screenshot(
            path: "/tmp/screen.png",
            payload: ScreenPayload(pngData: "abc", width: 100, height: 200, interface: nil),
            options: .init(includeInterface: true)
        ).humanFormatted()

        XCTAssertTrue(output.contains("✓ Screenshot saved: /tmp/screen.png"), output)
        XCTAssertTrue(output.contains("interface: unavailable"), output)
    }

}
