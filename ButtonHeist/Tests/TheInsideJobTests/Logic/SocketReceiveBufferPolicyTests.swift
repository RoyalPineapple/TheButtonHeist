import Foundation
import XCTest
import TheScore
@testable import TheInsideJob

final class SocketReceiveBufferPolicyTests: XCTestCase {
    func testServerPolicyUsesSharedClientToServerLimit() {
        XCTAssertEqual(
            SocketReceiveBufferPolicy.maxBufferedBytes,
            WireFrameLimits.clientToServerMaxBufferedBytes
        )
    }

    func testOversizedBatchIsRejectedBeforeFramerStateChanges() {
        let maximumContent = Data(
            repeating: UInt8(ascii: "x"),
            count: SocketReceiveBufferPolicy.maxBufferedBytes
        )
        XCTAssertNoThrow(
            try SocketReceiveBufferPolicy.validate(NewlineDelimitedFramer(), appending: maximumContent)
        )

        var framer = NewlineDelimitedFramer()
        _ = framer.append(Data("partial".utf8))

        XCTAssertThrowsError(try SocketReceiveBufferPolicy.validate(framer, appending: maximumContent)) { error in
            XCTAssertEqual(
                error as? SocketReceiveBufferPolicy.Violation,
                .frameTooLarge(
                    byteCount: SocketReceiveBufferPolicy.maxBufferedBytes + "partial".utf8.count,
                    maxBytes: SocketReceiveBufferPolicy.maxBufferedBytes
                )
            )
            XCTAssertEqual(
                error.localizedDescription,
                "received frame buffer exceeded 10000000 bytes (10000007 bytes)"
            )
        }
        XCTAssertEqual(framer.pendingData, Data("partial".utf8))
    }
}
