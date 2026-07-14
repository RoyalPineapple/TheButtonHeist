import Foundation
@testable import TheScore

package func testResponseEnvelopeData(
    _ message: ServerMessage,
    buttonHeistVersion version: String = buttonHeistVersion
) throws -> Data {
    try JSONEncoder().encode(ResponseEnvelope(
        buttonHeistVersion: version,
        message: message
    ))
}
