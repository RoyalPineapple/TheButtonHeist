import ArgumentParser

struct OutputOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output format: human, json, compact (default: human when interactive, json when piped)")
    var format: OutputFormat?
}

enum CLITimeoutDefaults {
    static let common: Double = 10
    static let wait: Double = common
}

/// Shared timeout option for commands that pass a per-request timeout to TheFence.
struct TimeoutOption: ParsableArguments {
    @Option(name: .shortAndLong, help: "Per-request timeout in seconds (default: \(Int(CLITimeoutDefaults.common)))")
    var timeout: Double = CLITimeoutDefaults.common
}
