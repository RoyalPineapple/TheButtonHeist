import ArgumentParser

struct ConnectionOptions: ParsableArguments {
    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Auth token from a previous connection")
    var token: String?

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false
}
