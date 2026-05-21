import TheScore

extension TheFence {

    /// Owns TheHandoff-backed connection projection for session-state reads.
    struct SessionConnectionState {
        let handoff: TheHandoff

        @ButtonHeistActor
        var snapshot: SessionConnectionSnapshot {
            SessionConnectionSnapshot(
                connected: handoff.isConnected,
                phase: sessionConnectionPhase,
                device: sessionDevicePayload,
                lastFailure: sessionFailurePayload
            )
        }

        @ButtonHeistActor
        private var sessionConnectionPhase: SessionConnectionPhase {
            switch handoff.connectionPhase {
            case .disconnected:
                return .disconnected
            case .connecting:
                return .connecting
            case .connected:
                return .connected
            case .failed:
                return .failed
            }
        }

        @ButtonHeistActor
        private var sessionDevicePayload: SessionDevicePayload? {
            handoff.connectedDevice.map { device in
                SessionDevicePayload(
                    deviceName: handoff.displayName(for: device),
                    appName: device.appName,
                    connectionType: device.connectionType,
                    shortId: device.shortId
                )
            }
        }

        @ButtonHeistActor
        private var sessionFailurePayload: SessionFailurePayload? {
            handoff.connectionDiagnosticFailure.map { failure in
                SessionFailurePayload(
                    errorCode: failure.failureCode,
                    phase: failure.phase,
                    retryable: failure.retryable,
                    message: failure.errorDescription,
                    hint: failure.hint
                )
            }
        }
    }
}
