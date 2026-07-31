import Foundation
import TheScore

public enum HeistDoctor {
    public static func diagnosis(for request: HeistRepairRequest) -> HeistRepairDiagnosis {
        RepairDiagnosisPipeline.run(request)
    }

    public static func diagnosis(
        lastPass: HeistResult,
        newFail: HeistResult,
        stepPath requestedStepPath: HeistExecutionPath? = nil
    ) throws -> HeistRepairDiagnosis {
        let lastPassReport = HeistReport.project(result: lastPass)
        let newFailReport = HeistReport.project(result: newFail)
        let currentStep = try selectedCurrentFailure(in: newFailReport, stepPath: requestedStepPath)
        let lastStep = try selectedLastSuccess(in: lastPassReport, matching: currentStep.path)
        let request = try HeistRepairRequest(
            lastSuccess: repairEvidence(from: lastStep),
            currentFailure: repairEvidence(from: currentStep)
        )
        return diagnosis(for: request)
    }

    private static func selectedCurrentFailure(
        in report: HeistReport,
        stepPath: HeistExecutionPath?
    ) throws -> HeistReport.Node {
        if let stepPath {
            guard let step = report.outputNodes.first(where: {
                $0.path == stepPath && $0.kind == .action
            }) else {
                throw HeistDoctorError.stepNotFound(path: stepPath)
            }
            guard step.status == .failed else {
                throw HeistDoctorError.stepStatus(path: stepPath, expected: .failed, actual: step.status)
            }
            return step
        }

        guard let failedPath = report.summary.abortedAtPath,
              let failed = report.outputNodes.first(where: { $0.path == failedPath })
        else {
            throw HeistDoctorError.noFailedStep
        }
        guard failed.kind == .action else {
            throw HeistDoctorError.nonActionStep(path: failed.path, kind: failed.kind)
        }
        return failed
    }

    private static func selectedLastSuccess(
        in report: HeistReport,
        matching stepPath: HeistExecutionPath
    ) throws -> HeistReport.Node {
        guard let step = report.outputNodes.first(where: {
            $0.path == stepPath && $0.kind == .action
        }) else {
            throw HeistDoctorError.stepNotFound(path: stepPath)
        }
        guard step.status == .passed else {
            throw HeistDoctorError.stepStatus(path: stepPath, expected: .passed, actual: step.status)
        }
        return step
    }

}

public enum HeistResultPairSelection {
    public struct Warning: Sendable, Equatable {
        public let recording: URL
        public let reason: String
    }

    case selected(
        lastPass: URL,
        newFail: URL,
        planFingerprint: String,
        warnings: [Warning]
    )
    case unavailable(warnings: [Warning])

    public var warnings: [Warning] {
        switch self {
        case .selected(_, _, _, let warnings), .unavailable(let warnings):
            warnings
        }
    }

    public static func select(
        lastPassDirectory: URL,
        newFailDirectory: URL
    ) throws -> Self {
        var warnings: [Warning] = []
        let passRecordings = try discover(in: lastPassDirectory, warnings: &warnings)
        let failRecordings: [Recording]
        if lastPassDirectory.standardizedFileURL == newFailDirectory.standardizedFileURL {
            failRecordings = passRecordings
        } else {
            failRecordings = try discover(in: newFailDirectory, warnings: &warnings)
        }

        let passes = passRecordings.filter(\.isPassed).sorted(by: newestFirst)
        let failures = failRecordings.filter(\.isFailed).sorted(by: newestFirst)
        for failure in failures {
            guard let lastPass = passes.first(where: {
                $0.planFingerprint == failure.planFingerprint
                    && $0.recordedAt < failure.recordedAt
            }) else {
                continue
            }
            return .selected(
                lastPass: lastPass.url,
                newFail: failure.url,
                planFingerprint: failure.planFingerprint,
                warnings: warnings
            )
        }
        return .unavailable(warnings: warnings)
    }

    private struct Recording {
        let url: URL
        let planFingerprint: String
        let recordedAt: Date
        let outcome: HeistExecutionOutcome

        var isPassed: Bool {
            outcome == .passed
        }

        var isFailed: Bool {
            guard case .failed = outcome else { return false }
            return true
        }
    }

    private static func discover(
        in directory: URL,
        warnings: inout [Warning]
    ) throws -> [Recording] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
              )
        else {
            throw HeistDoctorError.resultDirectoryNotFound(path: directory.path)
        }

        let urls = try enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  url.isCanonicalResultRecording,
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else {
                return nil
            }
            return url
        }.sorted { $0.path < $1.path }

        var recordings: [Recording] = []
        for url in urls {
            do {
                let recording = try HeistResultCodec.decode(contentsOf: url)
                recordings.append(Recording(
                    url: url,
                    planFingerprint: recording.planFingerprint,
                    recordedAt: recording.recordedAt,
                    outcome: recording.result.outcome
                ))
            } catch {
                warnings.append(Warning(recording: url, reason: String(describing: error)))
            }
        }
        return recordings
    }

    private static func newestFirst(_ lhs: Recording, _ rhs: Recording) -> Bool {
        if lhs.recordedAt != rhs.recordedAt {
            return lhs.recordedAt > rhs.recordedAt
        }
        return lhs.url.path > rhs.url.path
    }
}

public enum HeistDoctorError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case noFailedStep
    case resultDirectoryNotFound(path: String)
    case stepNotFound(path: HeistExecutionPath)
    case nonActionStep(path: HeistExecutionPath, kind: HeistExecutionStepKind)
    case stepStatus(
        path: HeistExecutionPath,
        expected: HeistExecutionStepStatus,
        actual: HeistExecutionStepStatus
    )
    case missingActionEvidence(path: HeistExecutionPath)
    case missingTarget(path: HeistExecutionPath)
    case missingActionResult(path: HeistExecutionPath)
    case missingObservationEvidence(path: HeistExecutionPath)

    public var description: String {
        switch self {
        case .noFailedStep:
            return "new failing result does not contain a failed step"
        case .resultDirectoryNotFound(let path):
            return "heist result directory not found: \(path)"
        case .stepNotFound(let path):
            return "no action step found at \(path)"
        case .nonActionStep(let path, let kind):
            return "step at \(path) is \(kind.rawValue); heist-doctor only repairs action steps"
        case .stepStatus(let path, let expected, let actual):
            return "step at \(path) is \(actual.rawValue); expected \(expected.rawValue)"
        case .missingActionEvidence(let path):
            return "action step at \(path) has no action evidence"
        case .missingTarget(let path):
            return "action step at \(path) has no durable target"
        case .missingActionResult(let path):
            return "action step at \(path) has no action result"
        case .missingObservationEvidence(let path):
            return "action step at \(path) has no observation evidence"
        }
    }

    public var errorDescription: String? {
        description
    }
}

private extension URL {
    var isCanonicalResultRecording: Bool {
        let name = lastPathComponent
        let suffix: String
        if name.hasSuffix(".json.gz") {
            suffix = ".json.gz"
        } else if name.hasSuffix(".json") {
            suffix = ".json"
        } else {
            return false
        }

        let stem = String(name.dropLast(suffix.count))
        guard let uuid = UUID(uuidString: stem) else { return false }
        return uuid.uuidString.caseInsensitiveCompare(stem) == .orderedSame
    }
}
