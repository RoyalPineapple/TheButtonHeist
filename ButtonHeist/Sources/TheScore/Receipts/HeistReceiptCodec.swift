import Foundation
import zlib

package struct HeistReceiptCodecLimits: Sendable, Equatable {
    package static let `default` = HeistReceiptCodecLimits(
        maxJSONBytes: 64 * 1024 * 1024,
        maxGzipCompressedBytes: 16 * 1024 * 1024,
        maxGzipDecompressedBytes: 64 * 1024 * 1024
    )

    package let maxJSONBytes: Int
    package let maxGzipCompressedBytes: Int
    package let maxGzipDecompressedBytes: Int

    package init(
        maxJSONBytes: Int = 64 * 1024 * 1024,
        maxGzipCompressedBytes: Int,
        maxGzipDecompressedBytes: Int
    ) {
        precondition(maxJSONBytes > 0, "maxJSONBytes must be positive")
        precondition(maxGzipCompressedBytes > 0, "maxGzipCompressedBytes must be positive")
        precondition(maxGzipDecompressedBytes > 0, "maxGzipDecompressedBytes must be positive")
        self.maxJSONBytes = maxJSONBytes
        self.maxGzipCompressedBytes = maxGzipCompressedBytes
        self.maxGzipDecompressedBytes = maxGzipDecompressedBytes
    }
}

public enum HeistReceiptCodec {
    public static func write(_ receipt: HeistExecutionResult, to url: URL) throws {
        let data = try encode(receipt, format: format(for: url))
        try data.write(to: url, options: .atomic)
    }

    public static func decode(contentsOf url: URL) throws -> HeistExecutionResult {
        try decode(contentsOf: url, limits: .default)
    }

    package static func decode(
        contentsOf url: URL,
        limits: HeistReceiptCodecLimits
    ) throws -> HeistExecutionResult {
        let format = format(for: url)
        let data: Data
        switch format {
        case .json:
            data = try readBoundedFile(
                url,
                maxBytes: limits.maxJSONBytes,
                tooLargeError: HeistReceiptCodecError.jsonDataTooLarge
            )
        case .gzipJSON:
            data = try readBoundedFile(
                url,
                maxBytes: limits.maxGzipCompressedBytes,
                tooLargeError: HeistReceiptCodecError.gzipCompressedDataTooLarge
            )
        }
        return try decode(data, format: format, limits: limits)
    }

    public static func decode(_ data: Data, format: HeistReceiptFormat = .json) throws -> HeistExecutionResult {
        try decode(data, format: format, limits: .default)
    }

    package static func decode(
        _ data: Data,
        format: HeistReceiptFormat = .json,
        limits: HeistReceiptCodecLimits
    ) throws -> HeistExecutionResult {
        let jsonData: Data
        switch format {
        case .json:
            guard data.count <= limits.maxJSONBytes else {
                throw HeistReceiptCodecError.jsonDataTooLarge(
                    limit: limits.maxJSONBytes,
                    observed: data.count
                )
            }
            jsonData = data
        case .gzipJSON:
            guard data.count <= limits.maxGzipCompressedBytes else {
                throw HeistReceiptCodecError.gzipCompressedDataTooLarge(
                    limit: limits.maxGzipCompressedBytes,
                    observed: data.count
                )
            }
            jsonData = try GzipCodec.decompress(data, maxBytes: limits.maxGzipDecompressedBytes)
        }
        return try JSONDecoder().decode(HeistExecutionResult.self, from: jsonData)
    }

    public static func encode(_ receipt: HeistExecutionResult, format: HeistReceiptFormat = .json) throws -> Data {
        let jsonData = try JSONEncoder.heistReceipt.encode(receipt)
        switch format {
        case .json:
            return jsonData
        case .gzipJSON:
            return try GzipCodec.compress(jsonData)
        }
    }

    private static func format(for url: URL) -> HeistReceiptFormat {
        url.pathExtension.lowercased() == "gz" ? .gzipJSON : .json
    }

    private static func readBoundedFile(
        _ url: URL,
        maxBytes: Int,
        tooLargeError: (Int, Int) -> HeistReceiptCodecError
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

public enum HeistReceiptFormat: Sendable, Equatable {
    case json
    case gzipJSON
}

public enum HeistReceiptCodecError: Error, Sendable, Equatable, CustomStringConvertible {
    case gzipInitializationFailed(operation: String, code: Int32)
    case gzipStreamFailed(operation: String, code: Int32)
    case jsonDataTooLarge(limit: Int, observed: Int)
    case gzipCompressedDataTooLarge(limit: Int, observed: Int)
    case gzipDecompressedDataTooLarge(limit: Int, observed: Int)
    case gzipCorruptData

    public var description: String {
        switch self {
        case .gzipInitializationFailed(let operation, let code):
            return "gzip \(operation) initialization failed with zlib code \(code)"
        case .gzipStreamFailed(let operation, let code):
            return "gzip \(operation) failed with zlib code \(code)"
        case .jsonDataTooLarge(let limit, let observed):
            return "JSON receipt data is too large (\(observed) bytes; limit \(limit) bytes)"
        case .gzipCompressedDataTooLarge(let limit, let observed):
            return "gzip receipt compressed data is too large (\(observed) bytes; limit \(limit) bytes)"
        case .gzipDecompressedDataTooLarge(let limit, let observed):
            return "gzip receipt decompressed data is too large (\(observed) bytes; limit \(limit) bytes)"
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
            throw HeistReceiptCodecError.gzipInitializationFailed(operation: "decompression", code: initStatus)
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
                        throw HeistReceiptCodecError.gzipDecompressedDataTooLarge(
                            limit: maxBytes,
                            observed: outputData.count + written
                        )
                    }
                    outputData.append(contentsOf: output.prefix(written))
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw HeistReceiptCodecError.gzipCorruptData
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
            throw HeistReceiptCodecError.gzipInitializationFailed(operation: "compression", code: initStatus)
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
                throw HeistReceiptCodecError.gzipStreamFailed(operation: "compression", code: status)
            }
            return outputData
        }
    }
}

private extension JSONEncoder {
    static var heistReceipt: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
