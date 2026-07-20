import Foundation
import zlib

package struct HeistResultCodecLimits: Sendable, Equatable {
    package static let `default` = HeistResultCodecLimits(
        maxJSONBytes: 64 * 1024 * 1024,
        maxGzipCompressedBytes: 16 * 1024 * 1024,
        maxGzipDecompressedBytes: 64 * 1024 * 1024,
        maxNodeCount: 100_000,
        maxNestingDepth: 64
    )

    package let maxJSONBytes: Int
    package let maxGzipCompressedBytes: Int
    package let maxGzipDecompressedBytes: Int
    package let maxNodeCount: Int
    package let maxNestingDepth: Int

    package init(
        maxJSONBytes: Int = 64 * 1024 * 1024,
        maxGzipCompressedBytes: Int,
        maxGzipDecompressedBytes: Int,
        maxNodeCount: Int = 100_000,
        maxNestingDepth: Int = 64
    ) {
        precondition(maxJSONBytes > 0, "maxJSONBytes must be positive")
        precondition(maxGzipCompressedBytes > 0, "maxGzipCompressedBytes must be positive")
        precondition(maxGzipDecompressedBytes > 0, "maxGzipDecompressedBytes must be positive")
        precondition(maxNodeCount > 0, "maxNodeCount must be positive")
        precondition(maxNestingDepth > 0, "maxNestingDepth must be positive")
        self.maxJSONBytes = maxJSONBytes
        self.maxGzipCompressedBytes = maxGzipCompressedBytes
        self.maxGzipDecompressedBytes = maxGzipDecompressedBytes
        self.maxNodeCount = maxNodeCount
        self.maxNestingDepth = maxNestingDepth
    }
}

public enum HeistResultCodec {
    public static func write(_ result: HeistResult, to url: URL) throws {
        let data = try encode(result, format: format(for: url))
        try data.write(to: url, options: .atomic)
    }

    public static func decode(contentsOf url: URL) throws -> HeistResult {
        try decode(contentsOf: url, limits: .default)
    }

    package static func decode(
        contentsOf url: URL,
        limits: HeistResultCodecLimits
    ) throws -> HeistResult {
        let format = format(for: url)
        let data: Data
        switch format {
        case .json:
            data = try readBoundedFile(
                url,
                maxBytes: limits.maxJSONBytes,
                tooLargeError: HeistResultCodecError.jsonDataTooLarge
            )
        case .gzipJSON:
            data = try readBoundedFile(
                url,
                maxBytes: limits.maxGzipCompressedBytes,
                tooLargeError: HeistResultCodecError.gzipCompressedDataTooLarge
            )
        }
        return try decode(data, format: format, limits: limits)
    }

    public static func decode(_ data: Data, format: HeistResultFormat = .json) throws -> HeistResult {
        try decode(data, format: format, limits: .default)
    }

    package static func decode(
        _ data: Data,
        format: HeistResultFormat = .json,
        limits: HeistResultCodecLimits
    ) throws -> HeistResult {
        let jsonData: Data
        switch format {
        case .json:
            guard data.count <= limits.maxJSONBytes else {
                throw HeistResultCodecError.jsonDataTooLarge(
                    limit: limits.maxJSONBytes,
                    observed: data.count
                )
            }
            jsonData = data
        case .gzipJSON:
            guard data.count <= limits.maxGzipCompressedBytes else {
                throw HeistResultCodecError.gzipCompressedDataTooLarge(
                    limit: limits.maxGzipCompressedBytes,
                    observed: data.count
                )
            }
            jsonData = try GzipCodec.decompress(data, maxBytes: limits.maxGzipDecompressedBytes)
        }
        let decoder = JSONDecoder()
        decoder.userInfo[.heistResultCodecLimits] = limits
        return try decoder.decode(HeistResult.self, from: jsonData)
    }

    public static func encode(_ result: HeistResult, format: HeistResultFormat = .json) throws -> Data {
        let jsonData = try JSONEncoder.heistResult.encode(result)
        switch format {
        case .json:
            return jsonData
        case .gzipJSON:
            return try GzipCodec.compress(jsonData)
        }
    }

    private static func format(for url: URL) -> HeistResultFormat {
        url.pathExtension.lowercased() == "gz" ? .gzipJSON : .json
    }

    private static func readBoundedFile(
        _ url: URL,
        maxBytes: Int,
        tooLargeError: (Int, Int) -> HeistResultCodecError
    ) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > maxBytes {
            throw tooLargeError(maxBytes, fileSize)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        while true {
            let remaining = maxBytes - data.count
            let readSize = min(GzipCodec.chunkSize, remaining + 1)
            guard let chunk = try handle.read(upToCount: readSize), !chunk.isEmpty else {
                return data
            }
            guard data.count + chunk.count <= maxBytes else {
                throw tooLargeError(maxBytes, data.count + chunk.count)
            }
            data.append(chunk)
        }
    }
}

public enum HeistResultFormat: Sendable, Equatable {
    case json
    case gzipJSON
}

public enum HeistResultCodecError: Error, Sendable, Equatable, CustomStringConvertible {
    case gzipInitializationFailed(operation: String, code: Int32)
    case gzipStreamFailed(operation: String, code: Int32)
    case jsonDataTooLarge(limit: Int, observed: Int)
    case gzipCompressedDataTooLarge(limit: Int, observed: Int)
    case gzipDecompressedDataTooLarge(limit: Int, observed: Int)
    case nodeCountExceeded(limit: Int, observed: Int)
    case nestingDepthExceeded(limit: Int, observed: Int)
    case duplicateExecutionPath(HeistExecutionPath)
    case nonDescendantChildPath(parent: HeistExecutionPath, child: HeistExecutionPath)
    case illegalRootExecutionPath(HeistExecutionPath)
    case illegalChildExecutionPath(
        parent: HeistExecutionPath,
        child: HeistExecutionPath,
        parentKind: HeistExecutionStepKind
    )
    case incoherentExecutionEvidence(path: HeistExecutionPath, reason: String)
    case gzipCorruptData

    public var description: String {
        switch self {
        case .gzipInitializationFailed(let operation, let code):
            return "gzip \(operation) initialization failed with zlib code \(code)"
        case .gzipStreamFailed(let operation, let code):
            return "gzip \(operation) failed with zlib code \(code)"
        case .jsonDataTooLarge(let limit, let observed):
            return "JSON result data is too large (\(observed) bytes; limit \(limit) bytes)"
        case .gzipCompressedDataTooLarge(let limit, let observed):
            return "gzip result compressed data is too large (\(observed) bytes; limit \(limit) bytes)"
        case .gzipDecompressedDataTooLarge(let limit, let observed):
            return "gzip result decompressed data is too large (\(observed) bytes; limit \(limit) bytes)"
        case .nodeCountExceeded(let limit, let observed):
            return "heist result contains too many nodes (\(observed); limit \(limit))"
        case .nestingDepthExceeded(let limit, let observed):
            return "heist result nesting is too deep (\(observed); limit \(limit))"
        case .duplicateExecutionPath(let path):
            return "heist result contains duplicate execution path \(path)"
        case .nonDescendantChildPath(let parent, let child):
            return "heist result child path \(child) is not a descendant of parent path \(parent)"
        case .illegalRootExecutionPath(let path):
            return "heist result root path \(path) is not a legal root step path"
        case .illegalChildExecutionPath(let parent, let child, let parentKind):
            return "heist result child path \(child) is not a legal \(parentKind.rawValue) child of \(parent)"
        case .incoherentExecutionEvidence(let path, let reason):
            return "heist result node \(path) has incoherent execution evidence: \(reason)"
        case .gzipCorruptData:
            return "gzip decompression failed: corrupt or truncated gzip data"
        }
    }
}

private enum GzipCodec {
    static let chunkSize = 64 * 1024
    private static let gzipWindowBits: Int32 = 15 + 16

    static func decompress(_ data: Data, maxBytes: Int) throws -> Data {
        var input = [UInt8](data)
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            gzipWindowBits,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw HeistResultCodecError.gzipInitializationFailed(operation: "decompression", code: initStatus)
        }
        defer { inflateEnd(&stream) }

        return try input.withUnsafeMutableBufferPointer { inputBuffer in
            stream.next_in = inputBuffer.baseAddress
            stream.avail_in = uInt(inputBuffer.count)
            var outputData = Data()
            var status: Int32 = Z_OK

            repeat {
                var output = [UInt8](repeating: 0, count: chunkSize)
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    stream.next_out = outputBuffer.baseAddress
                    stream.avail_out = uInt(outputBuffer.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                }
                let written = output.count - Int(stream.avail_out)
                if written > 0 {
                    guard outputData.count + written <= maxBytes else {
                        throw HeistResultCodecError.gzipDecompressedDataTooLarge(
                            limit: maxBytes,
                            observed: outputData.count + written
                        )
                    }
                    outputData.append(contentsOf: output.prefix(written))
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw HeistResultCodecError.gzipCorruptData
            }
            return outputData
        }
    }

    static func compress(_ data: Data) throws -> Data {
        var input = [UInt8](data)
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            gzipWindowBits,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw HeistResultCodecError.gzipInitializationFailed(operation: "compression", code: initStatus)
        }
        defer { deflateEnd(&stream) }

        return try input.withUnsafeMutableBufferPointer { inputBuffer in
            stream.next_in = inputBuffer.baseAddress
            stream.avail_in = uInt(inputBuffer.count)
            var outputData = Data()
            var status: Int32 = Z_OK

            repeat {
                var output = [UInt8](repeating: 0, count: chunkSize)
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    stream.next_out = outputBuffer.baseAddress
                    stream.avail_out = uInt(outputBuffer.count)
                    status = deflate(&stream, Z_FINISH)
                }
                let written = output.count - Int(stream.avail_out)
                if written > 0 {
                    outputData.append(contentsOf: output.prefix(written))
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw HeistResultCodecError.gzipStreamFailed(operation: "compression", code: status)
            }
            return outputData
        }
    }
}

private extension JSONEncoder {
    static var heistResult: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
