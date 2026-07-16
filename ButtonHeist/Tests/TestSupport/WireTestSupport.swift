import Foundation
@testable import TheScore

package func testResponseEnvelopeData(
    _ message: ServerMessage,
    buttonHeistVersion version: ButtonHeistVersion = buttonHeistVersion
) throws -> Data {
    try JSONEncoder().encode(ResponseEnvelope(
        buttonHeistVersion: version,
        message: message
    ))
}
