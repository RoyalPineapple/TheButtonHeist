import Foundation

/// Pure newline-delimited framing state shared by both socket directions.
///
/// Complete empty frames are ignored because an empty payload is not a Button Heist
/// wire message. The retained bytes are always the single suffix after the last
/// delimiter observed so far.
package struct NewlineDelimitedFramer: Equatable, Sendable {
    package private(set) var pendingData = Data()

    package var pendingByteCount: Int {
        pendingData.count
    }

    package init() {}

    package mutating func append(_ content: Data) -> [Data] {
        guard !content.isEmpty else { return [] }

        var frames: [Data] = []
        var sawDelimiter = false
        var segmentStart = 0

        for index in content.indices where content[index] == WireFrameLimits.newlineDelimiterByte {
            var frame = sawDelimiter ? Data() : pendingData
            if index > segmentStart {
                frame.append(contentsOf: content[segmentStart..<index])
            }
            if !frame.isEmpty {
                frames.append(frame)
            }
            segmentStart = index + 1
            sawDelimiter = true
        }

        if sawDelimiter {
            pendingData = Data(content.suffix(from: segmentStart))
        } else {
            pendingData.append(content)
        }

        return frames
    }
}
