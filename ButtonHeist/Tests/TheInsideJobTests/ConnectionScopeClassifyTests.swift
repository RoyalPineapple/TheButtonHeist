import Foundation
import Network
import Testing
@testable import TheInsideJob
import TheScore

@Suite("ConnectionScope.classify")
struct ConnectionScopeClassifyTests {

    private struct MockInterface: NetworkInterfaceNaming {
        let name: String
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

    // MARK: - classify with loopback interface

    @Test func classifiesLoopbackInterfaceAsSimulator() {
        let lo0 = MockInterface(name: "lo0")
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("169.254.239.217"), interfaces: [lo0]) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1"), interfaces: [lo0]) == .simulator)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100"), interfaces: [lo0]) == .simulator)
    }

    // MARK: - classify with interfaces (anpi detection)

    @Test func classifiesAnpiInterfaceAsUSB() {
        let anpi = MockInterface(name: "anpi0")
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fd9a:6190:eed7::1"), interfaces: [anpi]) == .usb)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100"), interfaces: [anpi]) == .usb)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("2001:db8::1"), interfaces: [anpi]) == .usb)
    }

    @Test func classifiesAnpiVariantsAsUSB() {
        let anpi1 = MockInterface(name: "anpi1")
        let anpi2 = MockInterface(name: "anpi2")
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1"), interfaces: [anpi1]) == .usb)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fe80::1"), interfaces: [anpi2]) == .usb)
    }

    @Test func nonAnpiInterfaceIsNotUSB() {
        let en0 = MockInterface(name: "en0")
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("fd9a:6190:eed7::1"), interfaces: [en0]) == .network)
        #expect(ConnectionScope.classify(host: NWEndpoint.Host("192.168.1.100"), interfaces: [en0]) == .network)
    }

    @Test func loopbackStillSimulatorWithAnpiInterface() {
        let anpi = MockInterface(name: "anpi0")
        #expect(ConnectionScope.classify(host: .ipv4(.loopback), interfaces: [anpi]) == .simulator)
        #expect(ConnectionScope.classify(host: .ipv6(.loopback), interfaces: [anpi]) == .simulator)
    }
}
