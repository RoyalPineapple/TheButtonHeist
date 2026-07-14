import Foundation

// MARK: - Output Helpers

/// Write to stderr (status messages)
func logStatus(_ message: String) {
    fputs("\(message)\n", stderr)
}

/// Write to stdout (data output)
func writeOutput(_ message: String) {
    print(message)
    fflush(stdout)
}

/// Write binary data to stdout.
func writeBinaryOutput(_ data: Data) {
    FileHandle.standardOutput.write(data)
}
