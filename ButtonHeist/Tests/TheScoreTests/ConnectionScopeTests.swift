import Foundation
import Testing
@testable import TheScore

@Suite("ConnectionScope")
struct ConnectionScopeTests {

    // MARK: - parse

    @Test func parsesSingleScope() {
        #expect(ConnectionScope.parse("simulator") == [.simulator])
        #expect(ConnectionScope.parse("usb") == [.usb])
        #expect(ConnectionScope.parse("network") == [.network])
    }

    @Test func parsesMultipleScopes() {
        #expect(ConnectionScope.parse("simulator,usb") == [.simulator, .usb])
        #expect(ConnectionScope.parse("simulator,usb,network") == ConnectionScope.all)
    }

    @Test func parsesWithWhitespace() {
        #expect(ConnectionScope.parse(" simulator , usb ") == [.simulator, .usb])
    }

    @Test func parsesWithMixedCase() {
        #expect(ConnectionScope.parse("Simulator,USB") == [.simulator, .usb])
    }

    @Test func parseReturnsNilForEmpty() {
        #expect(ConnectionScope.parse("") == nil)
    }

    @Test func parseReturnsNilForInvalid() {
        #expect(ConnectionScope.parse("bogus") == nil)
    }

    @Test func parseSkipsInvalidEntries() {
        #expect(ConnectionScope.parse("simulator,bogus,usb") == [.simulator, .usb])
    }

    @Test func parseReturnsNilWhenAllInvalid() {
        #expect(ConnectionScope.parse("foo,bar") == nil)
    }

    // MARK: - Static properties

    @Test func defaultScopesAreSimulatorAndUSB() {
        #expect(ConnectionScope.default == [.simulator, .usb])
    }

    @Test func allScopesContainsEverything() {
        #expect(ConnectionScope.all == [.simulator, .usb, .network])
    }

    // MARK: - Codable round-trip

    @Test func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for scope in ConnectionScope.allCases {
            let data = try encoder.encode(scope)
            let decoded = try decoder.decode(ConnectionScope.self, from: data)
            #expect(decoded == scope)
        }
    }
}
