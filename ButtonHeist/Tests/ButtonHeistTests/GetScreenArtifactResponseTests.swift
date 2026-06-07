import XCTest
@testable import ButtonHeist
import TheScore

final class GetScreenArtifactResponseTests: XCTestCase {

    @ButtonHeistActor
    func testDefaultGetScreenWritesArtifactAndOmitsInlineDataAndInterface() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Pay", traits: [.button]),
        ])
        let fence = Self.makeFence(
            tempDirectory: tempDirectory,
            pngData: pngBytes.base64EncodedString(),
            interface: interface
        )

        let response = try await fence.execute(command: .getScreen)

        guard case .screenshot(let path, let payload, let options) = response else {
            return XCTFail("Expected screenshot artifact response, got \(response)")
        }
        XCTAssertEqual(payload.width, 393)
        XCTAssertEqual(payload.height, 852)
        XCTAssertNil(payload.interface)
        XCTAssertFalse(options.includeInterface)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), pngBytes)

        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["path"] as? String, path)
        XCTAssertEqual(json["width"] as? Double, 393)
        XCTAssertEqual(json["height"] as? Double, 852)
        XCTAssertNil(json["pngData"])
        XCTAssertNil(json["interface"])
    }

    @ButtonHeistActor
    func testInlineGetScreenRequiresOptInAndInterfaceRequiresExplicitOptIn() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pngData = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Pay", traits: [.button]),
        ])
        let fence = Self.makeFence(tempDirectory: tempDirectory, pngData: pngData, interface: interface)

        let inlineResponse = try await fence.execute(command: .getScreen, values: [
            "inlineData": .bool(true),
        ])

        guard case .screenshotData(let inlinePayload, let inlineOptions) = inlineResponse else {
            return XCTFail("Expected inline screenshot response, got \(inlineResponse)")
        }
        XCTAssertEqual(inlinePayload.pngData, pngData)
        XCTAssertNil(inlinePayload.interface)
        XCTAssertFalse(inlineOptions.includeInterface)

        let inlineJson = publicJSONObject(inlineResponse)
        XCTAssertEqual(inlineJson["pngData"] as? String, pngData)
        XCTAssertNil(inlineJson["path"])
        XCTAssertNil(inlineJson["interface"])

        let includedInterfaceResponse = try await fence.execute(command: .getScreen, values: [
            "inlineData": .bool(true),
            "includeInterface": .bool(true),
        ])

        guard case .screenshotData(let includedInterfacePayload, let includedInterfaceOptions) = includedInterfaceResponse else {
            return XCTFail("Expected inline screenshot response with interface, got \(includedInterfaceResponse)")
        }
        XCTAssertEqual(includedInterfacePayload.pngData, pngData)
        XCTAssertEqual(includedInterfacePayload.interface?.projectedElements.count, 1)
        XCTAssertTrue(includedInterfaceOptions.includeInterface)
        XCTAssertNotNil(publicJSONObject(includedInterfaceResponse)["interface"])
    }

    @ButtonHeistActor
    func testInlineGetScreenRejectsOutputBeforeDispatch() async throws {
        let (fence, mockConnection) = makeConnectedFence()

        let response = try await fence.execute(command: .getScreen, values: [
            "inlineData": .bool(true),
            "output": .string("/tmp/buttonheist-screen.png"),
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected inline/output contract error, got \(response)")
        }
        XCTAssertEqual(
            message,
            "schema validation failed for inlineData/output: observed inlineData=true with output; " +
                "expected choose output for an artifact path or inlineData=true for inline PNG data, not both"
        )
        XCTAssertTrue(mockConnection.sent.isEmpty)
    }

    @ButtonHeistActor
    func testInlineGetScreenRejectsOversizePayloadBeforeDelivery() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let oversizedPayload = String(
            repeating: "A",
            count: TheFence.DecodeLimits.maxInlineScreenshotBase64Bytes + 1
        )
        let fence = Self.makeFence(
            tempDirectory: tempDirectory,
            pngData: oversizedPayload,
            interface: Interface(timestamp: Date(), tree: [])
        )

        let response = try await fence.execute(command: .getScreen, values: [
            "inlineData": .bool(true),
        ])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected oversize inline error, got \(response)")
        }
        XCTAssertTrue(message.contains("Inline screenshot payload is too large"))
        XCTAssertEqual(details?.errorCode, "screen.inline_payload_too_large")
        XCTAssertEqual(details?.phase, .client)
        XCTAssertEqual(details?.retryable, false)

        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorCode"] as? String, "screen.inline_payload_too_large")
        XCTAssertNil(json["pngData"])
        XCTAssertNil(json["path"])
    }

    @ButtonHeistActor
    func testGetScreenInvalidOutputThrowsTypedInvalidRequest() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fence = Self.makeFence(
            tempDirectory: tempDirectory,
            pngData: Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString(),
            interface: Interface(timestamp: Date(), tree: [])
        )

        do {
            _ = try await fence.execute(command: .getScreen, values: [
                "output": .string("/tmp/../buttonheist-screen.png"),
            ])
            XCTFail("Expected invalid output path to throw")
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid output path"))
        } catch {
            XCTFail("Expected FenceError.invalidRequest, got \(error)")
        }
    }

    @ButtonHeistActor
    func testGetScreenInvalidBase64ThrowsTypedServerError() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fence = Self.makeFence(
            tempDirectory: tempDirectory,
            pngData: "not base64",
            interface: Interface(timestamp: Date(), tree: [])
        )

        do {
            _ = try await fence.execute(command: .getScreen)
            XCTFail("Expected invalid screenshot base64 to throw")
        } catch let error as FenceError {
            guard case .serverError(let serverError) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(serverError.kind, .general)
            XCTAssertEqual(serverError.message, "Failed to decode screenshot data")
        } catch {
            XCTFail("Expected FenceError.serverError, got \(error)")
        }
    }

    private static func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-get-screen-\(UUID().uuidString)", isDirectory: true)
    }

    @ButtonHeistActor
    private static func makeFence(
        tempDirectory: URL,
        pngData: String,
        interface: Interface
    ) -> TheFence {
        let config = TheFence.Configuration(artifactBaseDirectory: tempDirectory)
        let (fence, mockConnection) = makeConnectedFence(configuration: config)
        mockConnection.autoResponse = { message in
            switch message {
            case .requestScreen:
                return .screen(ScreenPayload(
                    pngData: pngData,
                    width: 393,
                    height: 852,
                    interface: interface
                ))
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), tree: []))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        return fence
    }
}
