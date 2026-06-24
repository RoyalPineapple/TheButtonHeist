import Foundation
import Network
import os

import TheScore

private let connectionLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")

extension SimpleSocketServer {
    private static let maxConnections = 5

    func acceptReadyConnection(_ connection: NWConnection) -> Int? {
        if clientRegistry.count >= Self.maxConnections {
            connectionLogger.warning("Max connections (\(Self.maxConnections)) reached, rejecting")
            rejectStartedConnectionWithServerError(
                connection,
                kind: .general,
                message: "Connection rejected: server already has the maximum number of clients."
            )
            return nil
        }

        let scopeFilter = allowedScopes != ConnectionScope.all ? allowedScopes : nil
        if let scopeFilter {
            guard let host = Self.extractRemoteHost(from: connection) else {
                connectionLogger.warning("Cannot classify connection endpoint, rejecting (scope filter active)")
                rejectStartedConnectionWithServerError(
                    connection,
                    kind: .general,
                    message: "Connection rejected: server could not classify the connection scope."
                )
                return nil
            }
            let interfaceNameList = (connection.currentPath?.availableInterfaces ?? []).map { $0.name }
            let scope = ConnectionScope.classify(host: host, interfaceNames: interfaceNameList)
            let hostDescription = "\(host)"
            let interfaceNames = interfaceNameList.joined(separator: ", ")
            if !scopeFilter.contains(scope) {
                connectionLogger.warning("Rejecting \(scope.rawValue) connection from \(hostDescription) via [\(interfaceNames)]")
                rejectStartedConnectionWithServerError(
                    connection,
                    kind: .general,
                    message: "Connection rejected: \(scope.rawValue) connections are not allowed by this server."
                )
                return nil
            }
            connectionLogger.info("Accepted \(scope.rawValue) connection from \(hostDescription) via [\(interfaceNames)]")
        }

        let clientId = clientRegistry.insert(connection: connection)
        let remoteAddress = Self.extractRemoteHost(from: connection).map { "\($0)" }
        connectionLogger.info("Client \(clientId) connected")
        clientLifecycle.clientConnected(clientId, address: remoteAddress)
        startReceiving(clientId: clientId, connection: connection)
        return clientId
    }

    private func rejectStartedConnectionWithServerError(_ connection: NWConnection, kind: ErrorKind, message: String) {
        let response: Data
        do {
            response = try ResponseEnvelope(message: .error(TheScore.ServerError(kind: kind, message: message))).encoded()
        } catch {
            connectionLogger.error("Failed to encode connection rejection error: \(error.localizedDescription)")
            connection.cancel()
            return
        }

        var data = response
        if !data.hasSuffix(Data([WireFrameLimits.newlineDelimiterByte])) {
            data.append(WireFrameLimits.newlineDelimiterByte)
        }

        sendContent(connection, data, .contentProcessed { error in
            if let error {
                connectionLogger.error("Send error while rejecting unregistered connection: \(error)")
            }
            connection.cancel()
        })
    }

    /// Extract the remote host from an NWConnection using typed Network framework
    /// values. Checks the connection endpoint directly first, then currentPath.
    nonisolated private static func extractRemoteHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case .hostPort(let host, _) = connection.endpoint {
            return host
        }
        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
            return host
        }
        return nil
    }
}
