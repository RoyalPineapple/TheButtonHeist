#if canImport(UIKit)
#if DEBUG
@_exported import ButtonHeistDSL
import Darwin
import Foundation
import ObjectiveC
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
    try makeRunHeistArgumentRequest(
        name,
        argument: input,
        parameter: parameter,
        content
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
    try makeRunHeistArgumentRequest(
        name,
        argument: input,
        parameter: parameter,
        content
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
    try makeRunHeistArgumentRequest(
        name,
        argument: input,
        parameter: parameter,
        content
    )
}

private func makeRunHeistArgumentRequest<Argument: HeistRunArgument, Content: HeistContent>(
    _ name: String,
    argument input: Argument,
    parameter: HeistReferenceName,
    @HeistBuilder _ content: @escaping (Argument.Expression) throws -> Content
) throws -> HeistRunRequest {
    HeistRunRequest(
        plan: try shouldWrapDottedCapability(name)
            ? Argument.makeWrappedPlan(name, parameter: parameter, content: content)
            : Argument.makeNamedPlan(name, parameter: parameter, content: content),
        argument: try input.heistArgument()
    )
}

private protocol HeistRunArgument {
    associatedtype Expression

    func heistArgument() throws -> HeistArgument

    static func makeNamedPlan<Content: HeistContent>(
        _ name: String,
        parameter: HeistReferenceName,
        content: @escaping (Expression) throws -> Content
    ) throws -> HeistPlan

    static func makeWrappedPlan<Content: HeistContent>(
        _ name: String,
        parameter: HeistReferenceName,
        content: @escaping (Expression) throws -> Content
    ) throws -> HeistPlan
}

extension String: HeistRunArgument {
    typealias Expression = StringExpr

    func heistArgument() throws -> HeistArgument {
        .string(.literal(self))
    }

    static func makeNamedPlan<Content: HeistContent>(
        _ name: String,
        parameter: HeistReferenceName,
        content: @escaping (StringExpr) throws -> Content
    ) throws -> HeistPlan {
        try HeistPlan(name, parameter: parameter, content)
    }

    static func makeWrappedPlan<Content: HeistContent>(
        _ name: String,
        parameter: HeistReferenceName,
        content: @escaping (StringExpr) throws -> Content
    ) throws -> HeistPlan {
        let definition = HeistDef<String>(name, parameter: parameter, content)
        return try HeistPlan(parameter: parameter) { input in
            try definition(input)
        }
    }
}

private protocol ElementTargetHeistRunArgument: HeistRunArgument where Expression == ElementTargetExpr {}

extension ElementTargetHeistRunArgument {
    static func makeNamedPlan<Content: HeistContent>(
        _ name: String,
        parameter: HeistReferenceName,
        content: @escaping (ElementTargetExpr) throws -> Content
    ) throws -> HeistPlan {
        try HeistPlan(name, targetParameter: parameter, content)
    }

    static func makeWrappedPlan<Content: HeistContent>(
        _ name: String,
        parameter: HeistReferenceName,
        content: @escaping (ElementTargetExpr) throws -> Content
    ) throws -> HeistPlan {
        let definition = HeistDef<ElementTarget>(name, parameter: parameter, content)
        return try HeistPlan(targetParameter: parameter) { target in
            try definition(target)
        }
    }
}

extension ElementTarget: ElementTargetHeistRunArgument {
    typealias Expression = ElementTargetExpr

    func heistArgument() throws -> HeistArgument {
        .elementTarget(.target(self))
    }
}

extension ElementTargetExpr: ElementTargetHeistRunArgument {
    typealias Expression = ElementTargetExpr

    func heistArgument() throws -> HeistArgument {
        .elementTarget(.target(try resolve(in: .empty)))
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
    runHeistSyncArgument(
        name,
        argument: input,
        parameter: parameter,
        recordReceipt: recordReceipt,
        to: receiptDirectory,
        file: file,
        line: line,
        content
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
    runHeistSyncArgument(
        name,
        argument: input,
        parameter: parameter,
        recordReceipt: recordReceipt,
        to: receiptDirectory,
        file: file,
        line: line,
        content
    )
}

private func runHeistSyncArgument<Argument: HeistRunArgument, Content: HeistContent>(
    _ name: String,
    argument input: Argument,
    parameter: HeistReferenceName,
    recordReceipt: HeistTestReceiptRecording,
    to receiptDirectory: URL?,
    file: StaticString,
    line: UInt,
    @HeistBuilder _ content: @escaping (Argument.Expression) throws -> Content
) -> Heist? {
    runHeistSyncRequest(
        makeRequest: {
            try makeRunHeistArgumentRequest(
                name,
                argument: input,
                parameter: parameter,
                content
            )
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
    allowedScopes: Set<ConnectionScope> = [.simulator],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let session = startJoinedHeistSession(
        token: token,
        port: port,
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

func startJoinedHeistSession(
    token: String,
    port: UInt16,
    allowedScopes: Set<ConnectionScope>,
    file: StaticString,
    line: UInt
) -> JoinedHeistSession? {
    guard Thread.isMainThread else {
        XCTestRuntimeBridge.recordFailure(
            "joinHeist must be called on the main thread so it can pump the main run loop.",
            file: file,
            line: line
        )
        return nil
    }

    let state = HeistSyncState<JoinedHeistSession>()
    let task = Task { @MainActor in
        let job = TheInsideJob(
            token: token,
            allowedScopes: allowedScopes,
            port: port
        )
        do {
            try await job.start()
            guard let listeningPort = job.listeningPort else {
                state.finish(.failure(JoinHeistError.listenerDidNotReportPort))
                return
            }
            state.finish(.success(JoinedHeistSession(
                job: job,
                token: token,
                requestedPort: port,
                listeningPort: listeningPort,
                allowedScopes: allowedScopes
            )))
        } catch {
            state.finish(.failure(error))
        }
    }
    state.retain(task)

    return waitForSynchronousResult(state, file: file, line: line)
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
        XCTestRuntimeBridge.recordFailure("Heist failed before execution: \(error)", file: file, line: line)
        return nil
    }

    guard Thread.isMainThread else {
        XCTestRuntimeBridge.recordFailure(
            "runHeistSync must be called on the main thread so it can pump the main run loop.",
            file: file,
            line: line
        )
        return nil
    }

    let state = HeistSyncState<Heist>()
    let task = Task { @MainActor in
        do {
            let heist = try await Heist(request.plan, argument: request.argument)
            try recordReceiptIfRequested(
                heist.result,
                plan: request.plan,
                policy: recordReceipt,
                receiptDirectory: receiptDirectory
            )
            state.finish(.success(heist))
        } catch let failure as Heist.Failure {
            do {
                try recordReceiptIfRequested(
                    failure.result,
                    plan: request.plan,
                    policy: recordReceipt,
                    receiptDirectory: receiptDirectory
                )
                state.finish(.failure(failure))
            } catch {
                state.finish(.failure(HeistXCTestFailure(
                    primaryError: failure,
                    receiptRecordingError: error
                )))
            }
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
        XCTestRuntimeBridge.recordFailure(String(describing: error), file: file, line: line)
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

struct JoinedHeistSession {
    let job: TheInsideJob
    let token: String
    let requestedPort: UInt16
    let listeningPort: UInt16
    let allowedScopes: Set<ConnectionScope>

    @MainActor
    func stop() async {
        await job.stop()
    }

    var readyMessage: String {
        var lines = [
            "ButtonHeist join ready: endpoint=127.0.0.1:\(listeningPort) token=\(token)",
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
        lines.append("ButtonHeist join note: Bazel-launched simulators may still require external port forwarding from the host.")
        return lines.joined(separator: "\n")
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

private enum XCTestRuntimeBridge {
    private typealias CurrentTestCaseFunction = @convention(c) () -> AnyObject?
    private typealias CurrentIssueHandlerFunction = @convention(c) () -> AnyObject?
    private typealias ObjCNoArgumentFunction = @convention(c) (AnyObject, Selector) -> AnyObject
    private typealias SourceCodeLocationInitializerFunction = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
    private typealias SourceCodeContextInitializerFunction = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject
    private typealias IssueInitializerFunction = @convention(c) (
        AnyObject,
        Selector,
        Int,
        NSString,
        NSString?,
        AnyObject,
        AnyObject?,
        NSArray
    ) -> AnyObject
    private typealias RecordFailureFunction = @convention(c) (
        AnyObject,
        Selector,
        NSString,
        NSString,
        UInt,
        Bool
    ) -> Void
    private typealias HandleIssueFunction = @convention(c) (AnyObject, Selector, AnyObject) -> Void

    static func recordFailure(_ message: String, file: StaticString, line: UInt) {
        if recordFailureOnCurrentTestCase(message, file: file, line: line) {
            return
        }
        if recordFailureOnCurrentIssueHandler(message, file: file, line: line) {
            return
        }
        fputs("ButtonHeist XCTest failure bridge unavailable: \(message)\n", stderr)
    }

    private static func recordFailureOnCurrentTestCase(_ message: String, file: StaticString, line: UInt) -> Bool {
        guard let testCase = currentTestCase() else {
            return false
        }

        let selector = NSSelectorFromString("recordFailureWithDescription:inFile:atLine:expected:")
        guard testCase.responds(to: selector) else {
            return false
        }

        guard let messageSend = symbol(named: "objc_msgSend") else {
            return false
        }
        let recordFailure = unsafeBitCast(messageSend, to: RecordFailureFunction.self)
        recordFailure(
            testCase,
            selector,
            message as NSString,
            String(describing: file) as NSString,
            line,
            true
        )
        return true
    }

    private static func recordFailureOnCurrentIssueHandler(_ message: String, file: StaticString, line: UInt) -> Bool {
        guard let handler = currentIssueHandler(),
              let issue = makeAssertionFailureIssue(message, file: file, line: line),
              let messageSend = symbol(named: "objc_msgSend") else {
            return false
        }

        let handleIssue = unsafeBitCast(messageSend, to: HandleIssueFunction.self)
        for selectorName in ["handle:", "handleIssue:", "recordIssue:"] {
            let selector = NSSelectorFromString(selectorName)
            guard handler.responds(to: selector) else { continue }
            handleIssue(handler, selector, issue)
            return true
        }
        return false
    }

    private static func makeAssertionFailureIssue(_ message: String, file: StaticString, line: UInt) -> AnyObject? {
        guard let issueClass = NSClassFromString("XCTIssue"),
              let sourceCodeContext = makeSourceCodeContext(file: file, line: line),
              let messageSend = symbol(named: "objc_msgSend") else {
            return nil
        }
        let allocate = unsafeBitCast(messageSend, to: ObjCNoArgumentFunction.self)
        let initialize = unsafeBitCast(messageSend, to: IssueInitializerFunction.self)
        let allocatedIssue = allocate(issueClass, NSSelectorFromString("alloc"))
        return initialize(
            allocatedIssue,
            NSSelectorFromString("initWithType:compactDescription:detailedDescription:sourceCodeContext:associatedError:attachments:"),
            0,
            message as NSString,
            nil,
            sourceCodeContext,
            nil,
            NSArray()
        )
    }

    private static func makeSourceCodeContext(file: StaticString, line: UInt) -> AnyObject? {
        guard let locationClass = NSClassFromString("XCTSourceCodeLocation"),
              let contextClass = NSClassFromString("XCTSourceCodeContext"),
              let messageSend = symbol(named: "objc_msgSend") else {
            return nil
        }

        let allocate = unsafeBitCast(messageSend, to: ObjCNoArgumentFunction.self)
        let initializeLocation = unsafeBitCast(messageSend, to: SourceCodeLocationInitializerFunction.self)
        let allocatedLocation = allocate(locationClass, NSSelectorFromString("alloc"))
        let location = initializeLocation(
            allocatedLocation,
            NSSelectorFromString("initWithFilePath:lineNumber:"),
            String(describing: file) as NSString,
            Int(line)
        )

        let initializeContext = unsafeBitCast(messageSend, to: SourceCodeContextInitializerFunction.self)
        let allocatedContext = allocate(contextClass, NSSelectorFromString("alloc"))
        return initializeContext(
            allocatedContext,
            NSSelectorFromString("initWithLocation:"),
            location
        )
    }

    private static func currentIssueHandler() -> AnyObject? {
        guard let symbol = symbol(named: "_XCTCurrentIssueHandler") else {
            return nil
        }
        let function = unsafeBitCast(symbol, to: CurrentIssueHandlerFunction.self)
        return function()
    }

    private static func currentTestCase() -> AnyObject? {
        guard let symbol = symbol(named: "_XCTCurrentTestCase") else {
            return nil
        }
        let function = unsafeBitCast(symbol, to: CurrentTestCaseFunction.self)
        return function()
    }

    private static func symbol(named name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
