#if canImport(UIKit)
#if DEBUG
import Foundation

import TheInsideJob

/// Opens a ButtonHeist session and halts synchronous XCTest progression so a
/// human or agent can connect and interact with the app through MCP or the CLI.
/// Defaults to simulator loopback only; pass `allowedScopes` to opt into USB or
/// network clients.
///
/// This owns a fresh `TheInsideJob` instance instead of reconfiguring
/// `TheInsideJob.shared`, because `configure(...)` is intentionally ignored once
/// the singleton has been materialized by an earlier in-process heist.
public func joinHeist(
    token: String,
    port: UInt16 = 0,
    addressFamily: ListenerAddressFamily = .dualStack,
    allowedScopes: Set<ConnectionScope> = [.simulator],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let runtime = startJoinedHeistSession(
        token: token,
        port: port,
        addressFamily: addressFamily,
        allowedScopes: allowedScopes,
        file: file,
        line: line
    ) else {
        return
    }

    print(runtime.session.readyMessage)
    while true {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25))
    }
}

/// Opens a ButtonHeist session for the duration of `body` without halting test
/// progression.
///
/// The scoped session follows the same fresh-`TheInsideJob` startup path as
/// `joinHeist`, exposes the bound port and ready message to the caller, and
/// stops the session before returning or rethrowing from `body`.
@discardableResult
public func withJoinedHeistSession<Result>(
    token: String,
    port: UInt16 = 0,
    addressFamily: ListenerAddressFamily = .dualStack,
    allowedScopes: Set<ConnectionScope> = [.simulator],
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: (JoinedHeistSession) throws -> Result
) rethrows -> Result? {
    guard let runtime = startJoinedHeistSession(
        token: token,
        port: port,
        addressFamily: addressFamily,
        allowedScopes: allowedScopes,
        file: file,
        line: line
    ) else {
        return nil
    }

    defer {
        stopJoinedHeistSession(runtime, file: file, line: line)
    }
    return try body(runtime.session)
}

private func startJoinedHeistSession(
    token: String,
    port: UInt16,
    addressFamily: ListenerAddressFamily,
    allowedScopes: Set<ConnectionScope>,
    file: StaticString,
    line: UInt
) -> JoinedHeistRuntime? {
    runHeistSyncOperation(file: file, line: line) { @MainActor in
        let job = try TheInsideJob(
            token: token,
            allowedScopes: allowedScopes,
            port: port,
            addressFamily: addressFamily
        )
        try await job.start()
        guard let listeningPort = job.listeningPort else {
            throw JoinHeistError.listenerDidNotReportPort
        }
        let session = JoinedHeistSession(
            token: token,
            requestedPort: port,
            listeningPort: listeningPort,
            addressFamily: addressFamily,
            allowedScopes: allowedScopes
        )
        return JoinedHeistRuntime(job: job, session: session)
    }
}

private func stopJoinedHeistSession(
    _ runtime: JoinedHeistRuntime,
    file: StaticString,
    line: UInt
) {
    guard Thread.isMainThread else {
        recordHeistXCTestIssue(
            .joinedSessionRequiresMainThread,
            file: file,
            line: line
        )
        return
    }

    runHeistSyncOperation(file: file, line: line) { @MainActor in
        await runtime.stop()
    }
}

/// Immutable metadata for a scoped joined session.
public struct JoinedHeistSession: Sendable {
    public let token: String
    public let requestedPort: UInt16
    public let listeningPort: UInt16
    public let addressFamily: ListenerAddressFamily
    public let allowedScopes: Set<ConnectionScope>

    public var endpoint: String {
        "\(addressFamily.readyEndpointHost):\(listeningPort)"
    }

    public var readyMessage: String {
        var lines = [
            "ButtonHeist join ready: endpoint=\(endpoint) token=\(token)",
        ]
        if requestedPort != 0, requestedPort != listeningPort {
            lines.append("ButtonHeist join note: requested port \(requestedPort), bound port \(listeningPort).")
        }
        if allowedScopes == [.simulator] {
            lines.append("ButtonHeist join scope: simulator loopback only.")
        } else {
            let scopes = allowedScopes.map(\.rawValue).sorted().joined(separator: ",")
            lines.append("ButtonHeist join scopes: \(scopes).")
        }
        lines.append(
            "ButtonHeist join note: If this endpoint is unreachable from the host, "
                + "your launch system may require port forwarding."
        )
        return lines.joined(separator: "\n")
    }
}

private struct JoinedHeistRuntime: Sendable {
    let job: TheInsideJob
    let session: JoinedHeistSession

    @MainActor
    func stop() async {
        await job.stop()
    }
}

private extension ListenerAddressFamily {
    var readyEndpointHost: String {
        switch self {
        case .ipv4, .dualStack:
            return "127.0.0.1"
        case .ipv6:
            return "[::1]"
        }
    }
}

private enum JoinHeistError: Error, CustomStringConvertible {
    case listenerDidNotReportPort

    var description: String {
        switch self {
        case .listenerDidNotReportPort:
            return "TheInsideJob started, but no listening port was reported."
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
