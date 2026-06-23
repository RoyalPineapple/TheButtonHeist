import XCTest
import TheScore
@testable import TheInsideJob

final class SocketReceiveFramerTests: XCTestCase {
    func testDefaultMaxBufferedBytesUsesSharedClientToServerLimit() {
        XCTAssertEqual(
            SocketReceiveFramer.defaultMaxBufferedBytes,
            WireFrameLimits.clientToServerMaxBufferedBytes
        )
    }

    func testSuccessfulAppendLeavesOnlyUnfinishedSuffixAfterLastNewline() throws {
        var framer = SocketReceiveFramer(maxBufferedBytes: 64)

        let firstFrames = try framer.append(Data("first\nsecond".utf8))

        XCTAssertEqual(firstFrames.map(utf8String), ["first"])
        XCTAssertEqual(utf8String(framer.pendingData), "second")

        let secondFrames = try framer.append(Data("\nthird\npartial".utf8))

        XCTAssertEqual(secondFrames.map(utf8String), ["second", "third"])
        XCTAssertEqual(utf8String(framer.pendingData), "partial")
    }

    func testEmptyFramesAreDiscardedBeforeServerMessageHandling() throws {
        var framer = SocketReceiveFramer(maxBufferedBytes: 64)

        let frames = try framer.append(Data("\n\nbody\n".utf8))

        XCTAssertEqual(frames, [Data("body".utf8)])
        XCTAssertEqual(framer.pendingData, Data())
    }

    func testNilAppendReturnsNoFramesAndPreservesPendingData() throws {
        var framer = SocketReceiveFramer(maxBufferedBytes: 64, pendingData: Data("partial".utf8))

        let frames = try framer.append(nil)

        XCTAssertEqual(frames, [])
        XCTAssertEqual(utf8String(framer.pendingData), "partial")
    }

    func testOversizedAccumulationThrowsBeforeExtractingDelimitedFrame() {
        var framer = SocketReceiveFramer(maxBufferedBytes: 6)

        XCTAssertThrowsError(try framer.append(Data("123456\n".utf8))) { error in
            XCTAssertEqual(
                error as? SocketReceiveFramer.FramingError,
                .frameTooLarge(byteCount: 7, maxBytes: 6)
            )
            XCTAssertEqual(error.localizedDescription, "received frame buffer exceeded 6 bytes (7 bytes)")
        }
        XCTAssertEqual(framer.pendingData, Data())
    }

    func testOversizedAccumulationPreservesExistingPendingData() {
        var framer = SocketReceiveFramer(maxBufferedBytes: 10, pendingData: Data("abc".utf8))

        XCTAssertThrowsError(try framer.append(Data("12345678".utf8))) { error in
            XCTAssertEqual(
                error as? SocketReceiveFramer.FramingError,
                .frameTooLarge(byteCount: 11, maxBytes: 10)
            )
        }
        XCTAssertEqual(utf8String(framer.pendingData), "abc")
    }

    private func utf8String(_ data: Data) -> String {
        guard let string = String(bytes: data, encoding: .utf8) else {
            XCTFail("Expected UTF-8 data")
            return ""
        }
        return string
    }
}
