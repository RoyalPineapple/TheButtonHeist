import Foundation

import TheScore

enum HeistFileIO {

    static func write(_ heist: HeistPlan, to path: URL) throws {
        do {
            try HeistArtifactCodec.writePlan(heist, to: path)
        } catch {
            throw StorageError.heistRecording(.heistWriteFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }
    }
}

extension HeistStore {
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
