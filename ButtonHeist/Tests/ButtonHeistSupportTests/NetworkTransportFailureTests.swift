import Foundation
import Network
import XCTest

@testable import ButtonHeistSupport

final class NetworkTransportFailureTests: XCTestCase {
    func testPOSIXFailurePreservesTypedReasonAndDiagnostic() {
        let failure = NetworkTransportFailure(.posix(.ECONNRESET))

        XCTAssertEqual(failure.reason, .posix(code: Int(POSIXErrorCode.ECONNRESET.rawValue)))
        XCTAssertTrue(failure.description.hasPrefix("posix(\(POSIXErrorCode.ECONNRESET.rawValue)): "))
        XCTAssertEqual(failure.errorDescription, failure.description)
    }
}
