import Foundation
import Network
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

    // MARK: - classify (typed NWEndpoint.Host, no interfaces)

    @Test func classifiesIPv4Loopback() {
        #expect(ConnectionScope.classify(host: .ipv4(.loopback)) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("127.0.0.1")) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("127.0.0.2")) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("127.255.255.255")) == .simulator)
    }

    @Test func classifiesIPv6Loopback() {
        #expect(ConnectionScope.classify(host: .ipv6(.loopback)) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("::1")) == .simulator)
    }

@Test func classifiesPrivateIPv4AsNetwork() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100")) == .network)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("10.0.0.5")) == .network)
    }

    @Test func classifiesPublicIPv4AsNetwork() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("8.8.8.8")) == .network)
    }

    @Test func classifiesLinkLocalAsNetwork() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1")) == .network)
    }

    @Test func classifiesGlobalIPv6AsNetwork() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("2001:db8::1")) == .network)
    }

    @Test func classifiesHostnameAsNetwork() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("example.local")) == .network)
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
