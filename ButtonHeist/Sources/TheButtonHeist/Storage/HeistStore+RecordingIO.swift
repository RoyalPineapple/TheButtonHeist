import Foundation

import TheScore

extension HeistStore {

    func applyRecordingEffect(_ effect: HeistRecordingEffect) throws {
        switch effect {
        case .ignore:
            return
        case .dropPendingViewportSetup:
            try dropPendingViewportSetupSteps()
        case .append(let steps):
            try appendRecordingSteps(steps)
        }
    }

    func appendRecordingSteps(_ steps: [HeistStep]) throws {
        for step in steps {
            if step.isPendingViewportSetupCandidate {
                try appendPendingViewportSetupStep(step)
                continue
            }
            if step.dropsPendingViewportSetup {
                try dropPendingViewportSetupSteps()
            } else {
                try flushPendingViewportSetup()
            }
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

private extension HeistStep {
    var isPendingViewportSetupCandidate: Bool {
        guard case .action(let action) = self,
              action.expectation == nil,
              action.expectationWaiver == nil
        else { return false }
        switch action.command {
        case .viewportScroll, .viewportScrollToEdge:
            return true
        case .viewportScrollToVisible:
            return false
        case .activate, .increment, .decrement, .customAction, .rotor, .typeText,
             .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe, .mechanicalDrag,
             .editAction, .setPasteboard, .dismissKeyboard:
            return false
        }
    }

    var dropsPendingViewportSetup: Bool {
        guard case .action(let action) = self else { return false }
        switch action.command {
        case .activate, .increment, .decrement, .customAction, .rotor:
            return true
        case .typeText(_, let target):
            return target != nil
        case .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe, .mechanicalDrag,
             .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge,
             .editAction, .setPasteboard, .dismissKeyboard:
            return false
        }
    }
}
