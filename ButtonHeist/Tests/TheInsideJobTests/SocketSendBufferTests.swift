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

    func testCompletionConsumesTheExactAdmittedReservations() throws {
        var buffer = SocketSendBuffer(maxPendingBytes: 10)

        let first = try XCTUnwrap(admittedReservation(from: &buffer, byteCount: 4))
        let second = try XCTUnwrap(admittedReservation(from: &buffer, byteCount: 3))
        XCTAssertEqual(buffer.pendingBytes, 7)

        XCTAssertTrue(buffer.complete(first))
        XCTAssertEqual(buffer.pendingBytes, 3)
        XCTAssertTrue(buffer.complete(second))
        XCTAssertEqual(buffer.pendingBytes, 0)
    }

    func testReserveRejectsSinglePayloadAboveLimitWithoutChangingPendingBytes() throws {
        var buffer = SocketSendBuffer(maxPendingBytes: 10)
        _ = try XCTUnwrap(admittedReservation(from: &buffer, byteCount: 2))

        guard case .failure(let rejection) = buffer.reserve(byteCount: 11) else {
            return XCTFail("Expected payload-too-large rejection")
        }

        XCTAssertEqual(rejection, .payloadTooLarge(byteCount: 11, maxBytes: 10))
        XCTAssertEqual(buffer.pendingBytes, 2)
    }

    func testReserveRejectsWhenExistingPendingBytesWouldExceedLimit() throws {
        var buffer = SocketSendBuffer(maxPendingBytes: 10)
        _ = try XCTUnwrap(admittedReservation(from: &buffer, byteCount: 8))

        guard case .failure(let rejection) = buffer.reserve(byteCount: 3) else {
            return XCTFail("Expected buffer-full rejection")
        }

        XCTAssertEqual(rejection, .bufferFull(pendingBytes: 8, byteCount: 3, maxBytes: 10))
        XCTAssertEqual(buffer.pendingBytes, 8)
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

    private func admittedReservation(
        from buffer: inout SocketSendBuffer,
        byteCount: Int
    ) -> SocketSendBuffer.Reservation? {
        guard case .success(let reservation) = buffer.reserve(byteCount: byteCount) else {
            return nil
        }
        return reservation
    }
}
