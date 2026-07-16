import Foundation
import Testing
@testable import ThePlans

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

#if os(macOS) || os(Linux)
@Suite(.serialized)
struct CompilerProcessOwnerTests {
    @Test
    func `nonzero exit and signal termination are distinct outcomes`() async throws {
        let owner = CompilerProcessOwner()

        let nonzero = try await owner.run(
            shell("exit 23"),
            purpose: .execution,
            limits: limits()
        )
        let signaled = try await owner.run(
            shell("kill -KILL $$"),
            purpose: .execution,
            limits: limits()
        )

        guard case .nonzeroExit(let code, _) = nonzero else {
            Issue.record("Expected a nonzero exit, got \(nonzero)")
            return
        }
        guard case .signaled(let signal, _) = signaled else {
            Issue.record("Expected signal termination, got \(signaled)")
            return
        }
        #expect(code == 23)
        #expect(signal == SIGKILL)
    }

    @Test
    func `timeout escalates ignored termination and removes the process group`() async throws {
        let script = """
        trap '' TERM
        /bin/sh -c 'trap "" TERM; while :; do :; done' &
        while :; do :; done
        """
        let (processes, processContinuation) = AsyncStream<pid_t>.makeStream()
        let task = Task {
            try await CompilerProcessOwner().run(
                shell(script),
                purpose: .execution,
                limits: limits(executionTimeout: .milliseconds(100)),
                processStarted: { processContinuation.yield($0) }
            )
        }

        let processGroup = try #require(await processes.first { _ in true })
        processContinuation.finish()
        let outcome = try await task.value

        guard case .timedOut = outcome else {
            Issue.record("Expected timeout, got \(outcome)")
            return
        }
        #expect(processGroupExited(processGroup))
    }

    @Test
    func `task cancellation terminates and reaps the active process`() async throws {
        let command = shell("trap '' TERM; while :; do :; done")
        let (processes, processContinuation) = AsyncStream<pid_t>.makeStream()
        let task = Task {
            try await CompilerProcessOwner().run(
                command,
                purpose: .execution,
                limits: limits(executionTimeout: .seconds(10)),
                processStarted: { processContinuation.yield($0) }
            )
        }

        let processPID = try #require(await processes.first { _ in true })
        processContinuation.finish()
        task.cancel()
        let outcome = try await task.value

        guard case .cancelled = outcome else {
            Issue.record("Expected cancellation, got \(outcome)")
            return
        }
        #expect(processExited(processPID))
    }

    @Test
    func `large stdout and stderr are drained while retained output stays bounded`() async throws {
        let script = """
        i=0
        while [ "$i" -lt 10000 ]; do
          printf 'stdout-012345678901234567890123456789\n'
          printf 'stderr-012345678901234567890123456789\n' >&2
          i=$((i + 1))
        done
        """
        let byteLimit = 16_384
        let outcome = try await CompilerProcessOwner().run(
            shell(script),
            purpose: .execution,
            limits: limits(
                executionTimeout: .seconds(5),
                capturedByteLimitPerStream: byteLimit
            )
        )

        guard case .succeeded(let output) = outcome else {
            Issue.record("Expected successful output-heavy process, got \(outcome)")
            return
        }
        #expect(output.stdout.count == byteLimit)
        #expect(output.stderr.count == byteLimit)
        #expect(output.stdoutWasTruncated)
        #expect(output.stderrWasTruncated)
    }

    @Test
    func `compiler reports compilation deadline separately from execution deadline`() async throws {
        let temp = try ProcessTestTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan("NeverCompiled") { Warn("no") }
            }
            """
        )
        let configuration = HeistCompiler.Configuration(
            packageRoot: buttonHeistPackageRoot,
            processLimits: limits(compilationTimeout: .nanoseconds(1)),
            temporaryDirectory: temp.url
        )

        let result = await HeistCompiler(configuration: configuration).compileFile(source)
        let diagnostic = try #require(result.failureDiagnostics?.first)

        #expect(diagnostic.code.knownCode == .swiftCompilationCompileTimedOut)
        #expect(diagnostic.code.knownCode != .swiftCompilationExecutionTimedOut)
        #expect(try temp.generatedCompilerWorkspaces().isEmpty)
    }

    @Test
    func `compiler execution deadline removes its generated workspace`() async throws {
        let temp = try ProcessTestTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                while true {}
            }
            """
        )
        let configuration = HeistCompiler.Configuration(
            packageRoot: buttonHeistPackageRoot,
            processLimits: limits(
                compilationTimeout: .seconds(30),
                executionTimeout: .milliseconds(100)
            ),
            temporaryDirectory: temp.url
        )

        let result = await HeistCompiler(configuration: configuration).compileFile(source)
        let diagnostic = try #require(result.failureDiagnostics?.first)

        #expect(diagnostic.code.knownCode == .swiftCompilationExecutionTimedOut)
        #expect(try temp.generatedCompilerWorkspaces().isEmpty)
    }

    private func shell(
        _ script: String,
        arguments: [String] = []
    ) -> CompilerProcessCommand {
        CompilerProcessCommand(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "compiler-process-test"] + arguments
        )
    }

    private func limits(
        compilationTimeout: Duration = .seconds(5),
        executionTimeout: Duration = .seconds(2),
        capturedByteLimitPerStream: Int = 1_048_576
    ) -> CompilerProcessLimits {
        CompilerProcessLimits(
            compilationTimeout: compilationTimeout,
            executionTimeout: executionTimeout,
            terminationGrace: .milliseconds(50),
            killGrace: .seconds(1),
            pollInterval: .milliseconds(5),
            capturedByteLimitPerStream: capturedByteLimitPerStream
        )
    }

    private func processExited(_ processIdentifier: pid_t) -> Bool {
        kill(processIdentifier, 0) == -1 && errno == ESRCH
    }

    private func processGroupExited(_ processGroup: pid_t) -> Bool {
        kill(-processGroup, 0) == -1 && errno == ESRCH
    }

    private var buttonHeistPackageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class ProcessTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compiler-process-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func writeSwiftSource(_ source: String) throws -> URL {
        let sourceURL = url.appendingPathComponent("Plan.swift")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        return sourceURL
    }

    func generatedCompilerWorkspaces() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("heist-source-") }
    }
}

#endif
