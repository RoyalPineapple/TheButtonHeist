import ArgumentParser

struct OutputOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output format: human, json, compact (default: human when interactive, json when piped)")
    var format: OutputFormat?
}

/// Shared timeout option for commands that pass a per-request timeout to TheFence.
/// Use for the common 10s default; commands with non-default timeouts declare
/// their own option locally.
struct TimeoutOption: ParsableArguments {
    @Option(name: .shortAndLong, help: "Per-request timeout in seconds")
    var timeout: Double = 10.0
}
