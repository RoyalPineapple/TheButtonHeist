import Foundation
import Network
import Testing
@testable import TheInsideJob
import TheScore

@Suite("ConnectionScope.classify")
struct ConnectionScopeClassifyTests {

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

    // MARK: - classify with loopback interface

    @Test func classifiesLoopbackInterfaceAsSimulator() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("169.254.239.217"), interfaceNames: ["lo0"]) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1"), interfaceNames: ["lo0"]) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100"), interfaceNames: ["lo0"]) == .simulator)
    }

    // MARK: - classify with interfaces (anpi detection)

    @Test func classifiesAnpiInterfaceAsUSB() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fd9a:6190:eed7::1"), interfaceNames: ["anpi0"]) == .usb)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100"), interfaceNames: ["anpi0"]) == .usb)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("2001:db8::1"), interfaceNames: ["anpi0"]) == .usb)
    }

    @Test func classifiesAnpiVariantsAsUSB() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1"), interfaceNames: ["anpi1"]) == .usb)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1"), interfaceNames: ["anpi2"]) == .usb)
    }

    @Test func nonAnpiInterfaceIsNotUSB() {
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fd9a:6190:eed7::1"), interfaceNames: ["en0"]) == .network)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100"), interfaceNames: ["en0"]) == .network)
    }

    @Test func loopbackStillSimulatorWithAnpiInterface() {
        #expect(ConnectionScope.classify(host: .ipv4(.loopback), interfaceNames: ["anpi0"]) == .simulator)
        #expect(ConnectionScope.classify(host: .ipv6(.loopback), interfaceNames: ["anpi0"]) == .simulator)
    }
}
