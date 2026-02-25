import ArgumentParser
import Foundation

/// Shared connection options used by all commands that connect to a device.
/// Commands that also need `--format` and `--timeout` declare those individually
/// (defaults vary per command).
struct ConnectionOptions: ParsableArguments {
    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Flag(name: .long, help: "Force-takeover session from another driver")
    var force: Bool = false
}
