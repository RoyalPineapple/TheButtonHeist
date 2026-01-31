import Foundation

// Set up signal handling for clean shutdown
signal(SIGINT) { _ in
    print("\n👋 Exiting...")
    exit(0)
}

// Run on main actor
@MainActor
func startCLI() async {
    let runner = CLIRunner()
    await runner.run()
}

Task { @MainActor in
    await startCLI()
}

// Keep the run loop alive
RunLoop.main.run()
