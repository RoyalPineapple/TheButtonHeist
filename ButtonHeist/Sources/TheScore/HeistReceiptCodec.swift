import Foundation
import zlib

public enum HeistReceiptCodec {
    public static func write(_ receipt: HeistExecutionResult, to url: URL) throws {
        let data = try encode(receipt, format: format(for: url))
        try data.write(to: url, options: .atomic)
    }

    public static func decode(contentsOf url: URL) throws -> HeistExecutionResult {
        let data = try Data(contentsOf: url)
        return try decode(data, format: format(for: url))
    }

    public static func decode(_ data: Data, format: HeistReceiptFormat = .json) throws -> HeistExecutionResult {
        let jsonData: Data
        switch format {
        case .json:
            jsonData = data
        case .gzipJSON:
            jsonData = try GzipCodec.decompress(data)
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
}

public enum HeistReceiptFormat: Sendable, Equatable {
    case json
    case gzipJSON
}

public enum HeistReceiptCodecError: Error, Sendable, Equatable, CustomStringConvertible {
    case gzipInitializationFailed(operation: String, code: Int32)
    case gzipStreamFailed(operation: String, code: Int32)

    public var description: String {
        switch self {
        case .gzipInitializationFailed(let operation, let code):
            return "gzip \(operation) initialization failed with zlib code \(code)"
        case .gzipStreamFailed(let operation, let code):
            return "gzip \(operation) failed with zlib code \(code)"
        }
    }
}

private enum GzipCodec {
    private static let chunkSize = 64 * 1024
    private static let gzipWindowBits: Int32 = 15 + 16

    static func decompress(_ data: Data) throws -> Data {
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
                    outputData.append(contentsOf: output.prefix(written))
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw HeistReceiptCodecError.gzipStreamFailed(operation: "decompression", code: status)
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
