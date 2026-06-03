import Foundation

import TheScore

extension HeistStore {

    func appendRecordingSteps(_ steps: [HeistStep]) throws {
        for step in steps {
            try appendStep(step)
        }
    }

    // MARK: - Heist File I/O

    static func writeHeist(_ heist: HeistPlan, to path: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(heist)
            try PrivateStorage.writePrivateData(data, to: path)
        } catch {
            throw StorageError.heistRecording(.heistWriteFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }
    }

    static func readHeist(from path: URL) throws -> HeistPlan {
        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HeistPlan.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            throw StorageError.heistRecording(.heistReadFailed(
                path: path.path,
                reason: context.debugDescription
            ))
        } catch {
            throw StorageError.heistRecording(.heistReadFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }
    }

    // MARK: - Private Heist I/O

    func readSteps(from path: URL) throws -> [HeistStep] {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw StorageError.heistRecording(.stepReadFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }

        let lines = data.split(separator: 0x0A)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try lines.enumerated().map { index, lineData in
            do {
                return try decoder.decode(HeistStep.self, from: Data(lineData))
            } catch {
                throw StorageError.heistRecording(.stepReadFailed(
                    path: path.path,
                    reason: "line \(index + 1) is malformed: \(String(describing: error))"
                ))
            }
        }
    }
}
