import Foundation

public struct InsideJobAuthenticationPolicy: Equatable, Sendable {
    public static let `default` = InsideJobAuthenticationPolicy(admitted: ())

    let maximumFailedAttempts: Int
    let lockoutDuration: TimeInterval
    let failedAddressRetentionDuration: TimeInterval
    let maximumTrackedFailedAddresses: Int

    public init?(
        maximumFailedAttempts: Int = 5,
        lockoutDuration: TimeInterval = 30,
        failedAddressRetentionDuration: TimeInterval = 300,
        maximumTrackedFailedAddresses: Int = 1_024
    ) {
        guard maximumFailedAttempts > 0,
              lockoutDuration.isFinite,
              lockoutDuration > 0,
              failedAddressRetentionDuration.isFinite,
              failedAddressRetentionDuration > 0,
              maximumTrackedFailedAddresses > 0 else {
            return nil
        }
        self.maximumFailedAttempts = maximumFailedAttempts
        self.lockoutDuration = lockoutDuration
        self.failedAddressRetentionDuration = failedAddressRetentionDuration
        self.maximumTrackedFailedAddresses = maximumTrackedFailedAddresses
    }

    private init(admitted _: Void) {
        maximumFailedAttempts = 5
        lockoutDuration = 30
        failedAddressRetentionDuration = 300
        maximumTrackedFailedAddresses = 1_024
    }
}
