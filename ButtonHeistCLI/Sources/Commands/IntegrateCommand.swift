import ArgumentParser
import Foundation

struct IntegrateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "integrate",
        abstract: "Wire TheInsideJob into an iOS project using an AI coding agent",
        discussion: """
            Launches a coding agent that inspects your iOS project and adds \
            TheInsideJob as a dependency. The agent handles build system detection, \
            dependency wiring, Info.plist entries, and build verification.

            Supports multiple coding agents — pick your preferred model:

              buttonheist integrate                   # defaults to claude
              buttonheist integrate --agent gemini    # Gemini CLI (Google)
              buttonheist integrate --print-prompt    # print prompt, paste anywhere

            Agents:
              claude   Claude Code (Anthropic)       — default
              gemini   Gemini CLI (Google)
              codex    Codex CLI (OpenAI)
              copilot  GitHub Copilot CLI
              aider    Aider (open source)
            """
    )

    @Option(name: .long, help: "Coding agent to use: claude, gemini, codex, copilot, aider")
    var agent: AgentModel = .claude

    @Argument(help: "Path to the iOS project directory (defaults to current directory)")
    var projectDirectory: String?

    @Flag(name: .long, help: "Print the integration prompt and exit")
    var printPrompt: Bool = false

    @Flag(name: .long, help: "Write .mcp.json for Button Heist MCP server")
    var writeMcpConfig: Bool = false

    func run() throws {
        let projectPath = try resolveProjectDirectory()

        // Locate prebuilt frameworks — check Homebrew install, then local build
        let frameworksPath = try locateFrameworks()

        // Load prompt template and inject the frameworks path
        var prompt = loadIntegrationPrompt()
        prompt = prompt.replacingOccurrences(of: "{{FRAMEWORKS_PATH}}", with: frameworksPath)

        if printPrompt {
            print(prompt)
            return
        }

        // Preflight: check that the agent binary exists
        let binary = agent.binary
        guard commandExists(binary) else {
            throw ValidationError(
                "\(agent.displayName) not found on PATH. Install it with:\n  \(agent.installHint)"
            )
        }

        logStatus("▸ Using \(agent.displayName)")
        logStatus("▸ Target: \(projectPath)")
        logStatus("▸ Frameworks: \(frameworksPath)")

        if writeMcpConfig {
            try writeMcpJson(in: projectPath)
        }

        // Hand off to the agent — exec replaces this process so the agent
        // fully owns the TTY (stdin, stdout, stderr, /dev/tty).
        let arguments = agent.arguments(
            prompt: prompt,
            projectDirectory: projectPath,
            frameworksDirectory: frameworksPath
        )
        FileManager.default.changeCurrentDirectoryPath(projectPath)

        let argv = [binary] + arguments
        let cArgs = argv.map { strdup($0)! } + [nil]
        execvp(binary, cArgs)

        // execvp only returns on failure
        let errorCode = errno
        throw ValidationError("Failed to launch \(binary): \(String(cString: strerror(errorCode)))")
    }

    // MARK: - Framework Location

    /// The set of frameworks required by TheInsideJob.
    private static let requiredFrameworks = [
        "TheInsideJob.framework",
        "TheScore.framework",
        "AccessibilitySnapshotParser.framework",
        "AccessibilitySnapshotParser_ObjC.framework",
        "X509.framework",
        "Crypto.framework",
        "SwiftASN1.framework",
        "CCryptoBoringSSL.framework",
        "CCryptoBoringSSLShims.framework",
        "CryptoBoringWrapper.framework",
        "_CertificateInternals.framework",
        "_CryptoExtras.framework",
    ]

    private func locateFrameworks() throws -> String {
        // 1. Check next to the buttonheist binary (Homebrew install ships them here)
        // Resolve symlinks so Homebrew's /opt/homebrew/bin/buttonheist -> Cellar/... works
        let binaryURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        let binaryDir = binaryURL.deletingLastPathComponent().path
        let homebrewFrameworksDir = (binaryDir as NSString)
            .appendingPathComponent("ButtonHeistFrameworks")
        if hasAllFrameworks(in: homebrewFrameworksDir) {
            return homebrewFrameworksDir
        }

        // 2. Check the workspace DerivedData from a recent build
        let derivedDataRoot = NSString(
            string: "~/Library/Developer/Xcode/DerivedData"
        ).expandingTildeInPath
        if let derivedDataPath = latestDerivedData(in: derivedDataRoot),
           hasAllFrameworks(in: derivedDataPath) {
            return derivedDataPath
        }

        // Report which frameworks are missing and tailor advice to install method
        let missingFromHomebrew = Self.requiredFrameworks.filter { framework in
            let path = (homebrewFrameworksDir as NSString).appendingPathComponent(framework)
            var isDir: ObjCBool = false
            return !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue
        }

        let isHomebrewInstall = binaryDir.contains("/Cellar/") || binaryDir.contains("/homebrew/")
        let missingList = missingFromHomebrew.map { "  - \($0)" }.joined(separator: "\n")

        if isHomebrewInstall {
            throw ValidationError(
                """
                ButtonHeistFrameworks directory is missing or incomplete.
                Missing:\n\(missingList)

                Reinstall to get the frameworks:
                  brew reinstall royalpineapple/tap/buttonheist
                """
            )
        } else {
            throw ValidationError(
                """
                TheInsideJob frameworks not found. Build them first:
                  xcodebuild -workspace ButtonHeist.xcworkspace -scheme "BH Demo" \
                    -destination 'generic/platform=iOS Simulator' build
                Then re-run this command.

                Missing:\n\(missingList)
                """
            )
        }
    }

    private func hasAllFrameworks(in directory: String) -> Bool {
        let fileManager = FileManager.default
        return Self.requiredFrameworks.allSatisfy { framework in
            var isDir: ObjCBool = false
            let path = (directory as NSString).appendingPathComponent(framework)
            return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    private func latestDerivedData(in derivedDataRoot: String) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: derivedDataRoot) else {
            return nil
        }

        return contents
            .filter { $0.hasPrefix("ButtonHeist-") }
            .compactMap { dirName -> (String, Date)? in
                let productsDir = (derivedDataRoot as NSString)
                    .appendingPathComponent(dirName)
                    .appending("/Build/Products/Debug-iphonesimulator")
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: productsDir, isDirectory: &isDir),
                      isDir.boolValue else {
                    return nil
                }
                guard let attrs = try? fileManager.attributesOfItem(atPath: productsDir),
                      let modified = attrs[.modificationDate] as? Date else {
                    return nil
                }
                return (productsDir, modified)
            }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    // MARK: - Helpers

    private func loadIntegrationPrompt() -> String {
        IntegrationPrompt.text
    }

    private func resolveProjectDirectory() throws -> String {
        let path = projectDirectory ?? FileManager.default.currentDirectoryPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ValidationError("Directory not found: \(path)")
        }
        return (path as NSString).standardizingPath
    }

    private func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func writeMcpJson(in directory: String) throws {
        let mcpPath = (directory as NSString).appendingPathComponent(".mcp.json")
        if FileManager.default.fileExists(atPath: mcpPath) {
            let contents = try String(contentsOfFile: mcpPath, encoding: .utf8)
            if contents.contains("buttonheist") {
                logStatus("  ✓ .mcp.json already has buttonheist")
                return
            }
            logStatus("  ⚠ .mcp.json exists but no buttonheist entry — the agent will add it")
            return
        }

        guard commandExists("buttonheist-mcp") else {
            logStatus("  ⚠ Skipping .mcp.json — buttonheist-mcp not found on PATH")
            return
        }

        let config = """
            {
              "mcpServers": {
                "buttonheist": {
                  "command": "buttonheist-mcp",
                  "args": []
                }
              }
            }
            """
        try config.write(toFile: mcpPath, atomically: true, encoding: .utf8)
        logStatus("  ✓ Created .mcp.json")
    }
}

// MARK: - Agent Model

enum AgentModel: String, ExpressibleByArgument, CaseIterable, Sendable {
    case claude
    case gemini
    case codex
    case copilot
    case aider

    var binary: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .claude:  "Claude Code (Anthropic)"
        case .gemini:  "Gemini CLI (Google)"
        case .codex:   "Codex CLI (OpenAI)"
        case .copilot: "GitHub Copilot CLI"
        case .aider:   "Aider"
        }
    }

    var installHint: String {
        switch self {
        case .claude:  "npm install -g @anthropic-ai/claude-code"
        case .gemini:  "npm install -g @google/gemini-cli"
        case .codex:   "npm install -g @openai/codex"
        case .copilot: "npm install -g @github/copilot"
        case .aider:   "pip install aider-chat"
        }
    }

    /// Build the argument list for each agent CLI.
    ///
    /// Claude flags:
    /// - Interactive mode (positional prompt, not -p) for TUI rendering
    /// - `--permission-mode acceptEdits`: auto-approve file reads/edits
    /// - `--allowedTools`: pre-approve specific Bash commands
    /// - `--setting-sources user`: load user auth but skip project CLAUDE.md/.claude/
    /// - `--add-dir`: grant access to project dir and frameworks dir
    func arguments(prompt: String, projectDirectory: String, frameworksDirectory: String) -> [String] {
        switch self {
        case .claude:
            [
                prompt,
                "--permission-mode", "acceptEdits",
                "--allowedTools", "Bash(xcodebuild:*),Bash(cp:*),Bash(mkdir:*),Read,Write,Edit,Glob,Grep",
                "--setting-sources", "user",
                "--add-dir", projectDirectory,
                "--add-dir", frameworksDirectory,
            ]
        case .gemini:  ["-y", "-p", prompt]
        case .codex:   ["--approval-mode", "suggest", prompt]
        case .copilot: ["-p", prompt]
        case .aider:   ["--message", prompt]
        }
    }
}
