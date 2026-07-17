import Foundation
import Testing
import ThePlans

@testable import TheScore

@Test func identityStringCurrenciesPreserveExactValuesAndRoundTrip() throws {
    try assertIdentityValue(ContainerName.self)
    try assertIdentityValue(SessionAuthToken.self)
    try assertIdentityValue(DriverID.self)
    try assertIdentityValue(BundleIdentifier.self)
    try assertIdentityValue(ServerLaunchID.self)
    try assertIdentityValue(InsideJobInstanceID.self)
    try assertIdentityValue(InstallationID.self)
    try assertIdentityValue(SimulatorUDID.self)
    try assertIdentityValue(VendorIdentifier.self)
}

@Test func identityStringCurrenciesRejectBlankDynamicValues() {
    #expect(throws: (any Error).self) { try ContainerName(validating: " \n") }
    #expect(throws: (any Error).self) { try SessionAuthToken(validating: " \n") }
    #expect(throws: (any Error).self) { try DriverID(validating: "") }
    #expect(throws: (any Error).self) { try BundleIdentifier(validating: "\t") }
    #expect(throws: (any Error).self) { try ServerLaunchID(validating: " ") }
    #expect(throws: (any Error).self) { try InsideJobInstanceID(validating: "\n") }
    #expect(throws: (any Error).self) { try InstallationID(validating: "\r") }
    #expect(throws: (any Error).self) { try SimulatorUDID(validating: "  ") }
    #expect(throws: (any Error).self) { try VendorIdentifier(validating: "\t\n") }
}

private func assertIdentityValue<Value: NonBlankStringValue>(_ type: Value.Type) throws {
    let value = try Value(validating: " exact value ")
    #expect(value.description == " exact value ")
    #expect(try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value)) == value)
}
