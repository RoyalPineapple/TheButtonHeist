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

    // MARK: - classify

    @Test func classifiesIPv4Loopback() {
        #expect(ConnectionScope.classify(remoteAddress: "127.0.0.1") == .simulator)
        #expect(ConnectionScope.classify(remoteAddress: "127.0.0.2") == .simulator)
        #expect(ConnectionScope.classify(remoteAddress: "127.255.255.255") == .simulator)
    }

    @Test func classifiesIPv6Loopback() {
        #expect(ConnectionScope.classify(remoteAddress: "::1") == .simulator)
    }

    @Test func classifiesBracketedLoopback() {
        #expect(ConnectionScope.classify(remoteAddress: "[::1]") == .simulator)
        #expect(ConnectionScope.classify(remoteAddress: "[127.0.0.1]") == .simulator)
    }

    @Test func classifiesULAAsUSB() {
        #expect(ConnectionScope.classify(remoteAddress: "fd9a:6190:eed7::1") == .usb)
        #expect(ConnectionScope.classify(remoteAddress: "fdab:cdef:1234::2") == .usb)
    }

    @Test func classifiesBracketedULA() {
        #expect(ConnectionScope.classify(remoteAddress: "[fd9a:6190:eed7::1]") == .usb)
    }

    @Test func classifiesULACaseInsensitive() {
        #expect(ConnectionScope.classify(remoteAddress: "FD9A:6190:EED7::1") == .usb)
    }

    @Test func classifiesPrivateIPv4AsNetwork() {
        #expect(ConnectionScope.classify(remoteAddress: "192.168.1.100") == .network)
        #expect(ConnectionScope.classify(remoteAddress: "10.0.0.5") == .network)
    }

    @Test func classifiesPublicIPv4AsNetwork() {
        #expect(ConnectionScope.classify(remoteAddress: "8.8.8.8") == .network)
    }

    @Test func classifiesLinkLocalAsNetwork() {
        #expect(ConnectionScope.classify(remoteAddress: "fe80::1") == .network)
    }

    @Test func classifiesGlobalIPv6AsNetwork() {
        #expect(ConnectionScope.classify(remoteAddress: "2001:db8::1") == .network)
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
