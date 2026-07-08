#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

// Package contract: app-hosted tests import ButtonHeistTesting and author
// heists directly. Re-exporting the DSL here is intentional and allowlisted by
// scripts/check-buttonheist-import-contract.sh.
@_exported import ButtonHeistDSL
import ThePlans
import TheInsideJob

/// Prepared in-process heist execution request used by the testing facade.
///
/// `runHeist` lowers Swift test code to the same validated `HeistPlan` shape as
/// external heist execution, then executes it directly through `TheInsideJob`
/// in the app process. It does not cross the `TheFence`/network boundary.
struct HeistRunRequest: Equatable, Sendable {
    let plan: HeistPlan
    let argument: HeistArgument
}

@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    @HeistBuilder _ content: @escaping () throws -> Content
) async throws -> Heist {
    let request = try makeRunHeistRequest(name, content)
    return try await Heist(request.plan, argument: request.argument)
}

/// Runs a prebuilt in-process heist plan through the app-hosted test runtime.
@MainActor
@discardableResult
public func runHeist(
    _ plan: HeistPlan,
    argument: HeistArgument = .none
) async throws -> Heist {
    try await Heist(plan, argument: argument)
}

func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    @HeistBuilder _ content: @escaping () throws -> Content
) throws -> HeistRunRequest {
    guard shouldWrapDottedCapability(name) else {
        return HeistRunRequest(
            plan: try HeistPlan(name, content),
            argument: .none
        )
    }
    let definition = HeistDef<Void>(name, content)
    return HeistRunRequest(
        plan: try HeistPlan {
            try definition()
        },
        argument: .none
    )
}

@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        name,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(request.plan, argument: request.argument)
}

func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
) throws -> HeistRunRequest {
    HeistRunRequest(
        plan: try makeRunHeistPlan(name, parameter: parameter, content: content),
        argument: .string(.literal(input))
    )
}

@_disfavoredOverload
@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    argument input: ElementTarget,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) async throws -> Heist {
    try await runHeist(
        name,
        argument: .target(input),
        parameter: parameter,
        content
    )
}

@_disfavoredOverload
func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    argument input: ElementTarget,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) throws -> HeistRunRequest {
    HeistRunRequest(
        plan: try makeRunHeistPlan(name, targetParameter: parameter, content: content),
        argument: .elementTarget(.target(input))
    )
}

@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    argument input: ElementTargetExpr,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        name,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(request.plan, argument: request.argument)
}

func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    argument input: ElementTargetExpr,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) throws -> HeistRunRequest {
    let plan = try makeRunHeistPlan(name, targetParameter: parameter, content: content)
    return HeistRunRequest(
        plan: plan,
        argument: .elementTarget(.target(try input.resolve(in: .empty)))
    )
}

private func makeRunHeistPlan<Content: HeistContent>(
    _ name: String,
    parameter: HeistReferenceName,
    content: @escaping (StringExpr) throws -> Content
) throws -> HeistPlan {
    guard shouldWrapDottedCapability(name) else {
        return try HeistPlan(name, parameter: parameter, content)
    }
    let definition = HeistDef<String>(name, parameter: parameter, content)
    return try HeistPlan(parameter: parameter) { input in
        try definition(input)
    }
}

private func makeRunHeistPlan<Content: HeistContent>(
    _ name: String,
    targetParameter parameter: HeistReferenceName,
    content: @escaping (ElementTargetExpr) throws -> Content
) throws -> HeistPlan {
    guard shouldWrapDottedCapability(name) else {
        return try HeistPlan(name, targetParameter: parameter, content)
    }
    let definition = HeistDef<ElementTarget>(name, parameter: parameter, content)
    return try HeistPlan(targetParameter: parameter) { target in
        try definition(target)
    }
}

private func shouldWrapDottedCapability(_ name: String) -> Bool {
    name.split(separator: ".").count > 1
}

/// XCTest-facing receipt recording policy for synchronous heist helpers.
///
/// Use `.always` when a passing run should leave proof of the exact interface
/// it matched. This is useful in app-hosted test processes where environment
/// variables such as `BUTTONHEIST_RECEIPTS_MODE` and `BUTTONHEIST_RECEIPTS_DIR`
/// may not be inherited from the test runner.
public enum HeistTestReceiptRecording: Sendable, Equatable {
    /// Use the normal `BUTTONHEIST_RECEIPTS_MODE` / `BUTTONHEIST_RECEIPTS_DIR`
    /// environment-variable behavior.
    case environment
    /// Write only failed heist receipts to the supplied directory.
    case failures
    /// Write failed and passing heist receipts to the supplied directory.
    case always

    fileprivate var explicitRecorderMode: HeistReceiptRecordingMode? {
        switch self {
        case .environment:
            return nil
        case .failures:
            return .failures
        case .always:
            return .all
        }
    }
}

/// Synchronously runs an in-process heist from a plain XCTest method.
///
/// This helper intentionally keeps the XCTest method synchronous and pumps the
/// current run loop while the heist runs on the main actor. In app-hosted
/// XCTest/KIF-style targets, converting these tests to `async` can expose an
/// XCTest async-task teardown crash at process exit, especially when the app is
/// also doing background cleanup. Keep the test method synchronous unless the
/// host target has proven its async teardown path is safe.
///
/// On failure, this records an `XCTFail` at the call site and returns `nil`.
/// The failure message includes the heist failure description, including the
/// settled interface dump when one is available.
@discardableResult
public func runHeistSync<Content: HeistContent>(
    _ name: String,
    recordReceipt: HeistTestReceiptRecording = .environment,
    to receiptDirectory: URL? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    @HeistBuilder _ content: @escaping () throws -> Content
) -> Heist? {
    runHeistSyncRequest(
        makeRequest: { try makeRunHeistRequest(name, content) },
        recordReceipt: recordReceipt,
        receiptDirectory: receiptDirectory,
        file: file,
        line: line
    )
}

/// Synchronously runs a string-argument heist from a plain XCTest method.
@discardableResult
public func runHeistSync<Content: HeistContent>(
    _ name: String,
    argument input: String,
    parameter: HeistReferenceName = "input",
    recordReceipt: HeistTestReceiptRecording = .environment,
    to receiptDirectory: URL? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
) -> Heist? {
    runHeistSyncRequest(
        makeRequest: {
            try makeRunHeistRequest(name, argument: input, parameter: parameter, content)
        },
        recordReceipt: recordReceipt,
        receiptDirectory: receiptDirectory,
        file: file,
        line: line
    )
}

/// Synchronously runs an element-target heist from a plain XCTest method.
@_disfavoredOverload
@discardableResult
public func runHeistSync<Content: HeistContent>(
    _ name: String,
    argument input: ElementTarget,
    parameter: HeistReferenceName = "input",
    recordReceipt: HeistTestReceiptRecording = .environment,
    to receiptDirectory: URL? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) -> Heist? {
    runHeistSyncRequest(
        makeRequest: {
            try makeRunHeistRequest(name, argument: input, parameter: parameter, content)
        },
        recordReceipt: recordReceipt,
        receiptDirectory: receiptDirectory,
        file: file,
        line: line
    )
}

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
    guard let session = startJoinedHeistSession(
        token: token,
        port: port,
        addressFamily: addressFamily,
        allowedScopes: allowedScopes,
        file: file,
        line: line
    ) else {
        return
    }

    print(session.readyMessage)
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
    guard let session = startJoinedHeistSession(
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
        stopJoinedHeistSession(session, file: file, line: line)
    }
    return try body(session)
}

func startJoinedHeistSession(
    token: String,
    port: UInt16,
    addressFamily: ListenerAddressFamily,
    allowedScopes: Set<ConnectionScope>,
    file: StaticString,
    line: UInt
) -> JoinedHeistSession? {
    runHeistSyncOperation(file: file, line: line) { @MainActor in
        let job = TheInsideJob(
            token: token,
            allowedScopes: allowedScopes,
            port: port,
            addressFamily: addressFamily
        )
        try await job.start()
        guard let listeningPort = job.listeningPort else {
            throw JoinHeistError.listenerDidNotReportPort
        }
        return JoinedHeistSession(
            job: job,
            token: token,
            requestedPort: port,
            listeningPort: listeningPort,
            addressFamily: addressFamily,
            allowedScopes: allowedScopes
        )
    }
}

func stopJoinedHeistSession(
    _ session: JoinedHeistSession,
    file: StaticString,
    line: UInt
) {
    guard Thread.isMainThread else {
        XCTFail(
            "Joined heist sessions must stop on the main thread so the main run loop can be pumped.",
            file: file,
            line: line
        )
        return
    }

    runHeistSyncOperation(file: file, line: line) { @MainActor in
        await session.stop()
    }
}

private func runHeistSyncRequest(
    makeRequest: () throws -> HeistRunRequest,
    recordReceipt: HeistTestReceiptRecording,
    receiptDirectory: URL?,
    file: StaticString,
    line: UInt
) -> Heist? {
    let request: HeistRunRequest
    do {
        request = try makeRequest()
    } catch {
        XCTFail("Heist failed before execution: \(error)", file: file, line: line)
        return nil
    }

    guard Thread.isMainThread else {
        XCTFail(
            "runHeistSync must be called on the main thread so it can pump the main run loop.",
            file: file,
            line: line
        )
        return nil
    }

    return runHeistSyncOperation(file: file, line: line) { @MainActor in
        do {
            let heist = try await Heist(request.plan, argument: request.argument)
            try recordReceiptIfRequested(
                heist.result,
                plan: request.plan,
                policy: recordReceipt,
                receiptDirectory: receiptDirectory
            )
            return heist
        } catch let failure as Heist.Failure {
            do {
                try recordReceiptIfRequested(
                    failure.result,
                    plan: request.plan,
                    policy: recordReceipt,
                    receiptDirectory: receiptDirectory
                )
            } catch {
                throw HeistXCTestFailure(
                    primaryError: failure,
                    receiptRecordingError: error
                )
            }
            throw failure
        }
    }
}

@discardableResult
func runHeistSyncOperation<Value>(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: @escaping @Sendable () async throws -> Value
) -> Value? {
    guard Thread.isMainThread else {
        XCTFail(
            "runHeistSyncOperation must be called on the main thread so it can pump the main run loop.",
            file: file,
            line: line
        )
        return nil
    }

    let state = HeistSyncState<Value>()
    let task = Task {
        do {
            state.finish(.success(try await operation()))
        } catch {
            state.finish(.failure(error))
        }
    }
    state.retain(task)

    return waitForSynchronousResult(state, file: file, line: line)
}

private func waitForSynchronousResult<Value>(
    _ state: HeistSyncState<Value>,
    file: StaticString,
    line: UInt
) -> Value? {
    while state.result == nil {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    switch state.result {
    case .success(let value):
        return value
    case .failure(let error):
        XCTFail(String(describing: error), file: file, line: line)
        return nil
    case nil:
        return nil
    }
}

private func recordReceiptIfRequested(
    _ result: HeistExecutionResult,
    plan: HeistPlan,
    policy: HeistTestReceiptRecording,
    receiptDirectory: URL?
) throws {
    guard let mode = policy.explicitRecorderMode else { return }
    let rootDirectory = receiptDirectory ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("buttonheist-receipts", isDirectory: true)
    _ = try HeistReceiptRecorder.write(
        result,
        plan: plan,
        configuration: HeistReceiptRecordingConfiguration(
            rootDirectory: rootDirectory,
            mode: mode
        )
    )
}

/// `@unchecked Sendable` justification: the synchronous XCTest thread polls the
/// result while the retained main-actor task finishes it; `lock` protects all
/// mutable state shared across those isolation domains.
private final class HeistSyncState<Value>: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private var storage: Result<Value, Error>?
    private var task: Task<Void, Never>?

    var result: Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard storage == nil else { return }
        storage = result
    }

    func retain(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
    }
}

private struct HeistXCTestFailure: Error, CustomStringConvertible {
    let primaryError: Error
    let receiptRecordingError: Error

    var description: String {
        "\(primaryError)\nreceipt recording failed: \(receiptRecordingError)"
    }
}

/// Scoped join session metadata plus the main-actor runtime handle that owns the
/// temporary in-process server.
public struct JoinedHeistSession: Sendable {
    let job: TheInsideJob
    public let token: String
    public let requestedPort: UInt16
    public let listeningPort: UInt16
    public let addressFamily: ListenerAddressFamily
    public let allowedScopes: Set<ConnectionScope>

    @MainActor
    func stop() async {
        await job.stop()
    }

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
        lines.append("ButtonHeist join note: If this endpoint is unreachable from the host, your launch system may require port forwarding.")
        return lines.joined(separator: "\n")
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
