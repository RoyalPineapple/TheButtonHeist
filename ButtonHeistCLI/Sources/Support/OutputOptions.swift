import ArgumentParser

/// Shared output format option. Timeout is declared per-command since defaults vary.
struct OutputOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?
}
