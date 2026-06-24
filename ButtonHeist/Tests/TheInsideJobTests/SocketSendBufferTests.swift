import XCTest
import TheScore
@testable import TheInsideJob

final class SocketSendBufferTests: XCTestCase {
    func testDefaultMaxPendingBytesUsesSharedServerToClientLimit() {
        XCTAssertEqual(
            SocketSendBuffer.defaultMaxPendingBytes,
            WireFrameLimits.serverToClientMaxPendingSendBytes
        )
    }

    func testReserveIncrementsPendingBytesUntilCompleted() {
        var buffer = SocketSendBuffer(maxPendingBytes: 10)

        XCTAssertNil(buffer.reserve(byteCount: 4))
        XCTAssertEqual(buffer.pendingBytes, 4)

        buffer.complete(byteCount: 3)
        XCTAssertEqual(buffer.pendingBytes, 1)
    }

    func testReserveRejectsSinglePayloadAboveLimitWithoutChangingPendingBytes() {
        var buffer = SocketSendBuffer(maxPendingBytes: 10, pendingBytes: 2)

        let rejection = buffer.reserve(byteCount: 11)

        XCTAssertEqual(rejection, .payloadTooLarge(byteCount: 11, maxBytes: 10))
        XCTAssertEqual(buffer.pendingBytes, 2)
    }

    func testReserveRejectsWhenExistingPendingBytesWouldExceedLimit() {
        var buffer = SocketSendBuffer(maxPendingBytes: 10, pendingBytes: 8)

        let rejection = buffer.reserve(byteCount: 3)

        XCTAssertEqual(rejection, .bufferFull(pendingBytes: 8, byteCount: 3, maxBytes: 10))
        XCTAssertEqual(buffer.pendingBytes, 8)
    }

    func testCompleteClampsPendingBytesAtZero() {
        var buffer = SocketSendBuffer(maxPendingBytes: 10, pendingBytes: 2)

        buffer.complete(byteCount: 5)

        XCTAssertEqual(buffer.pendingBytes, 0)
    }

    func testRejectionMapsToPublicSendFailure() {
        XCTAssertEqual(
            SocketSendBuffer.Rejection.payloadTooLarge(byteCount: 11, maxBytes: 10).sendFailure,
            .payloadTooLarge(byteCount: 11, maxBytes: 10)
        )
        XCTAssertEqual(
            SocketSendBuffer.Rejection.bufferFull(pendingBytes: 8, byteCount: 3, maxBytes: 10).sendFailure,
            .sendBufferFull(pendingBytes: 8, byteCount: 3, maxBytes: 10)
        )
    }
}
