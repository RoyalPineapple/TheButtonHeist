import Foundation
import XCTest

final class CITestTopologyContractTests: XCTestCase {
    func testHostedTestSourcesArePartitionedByTargetMembership() throws {
        let project = try contents(relativePath: "Project.swift")

        XCTAssertTrue(project.contains("name: \"TheInsideJobTests\""))
        XCTAssertTrue(project.contains("name: \"TheInsideJobIntegrationTests\""))
        XCTAssertTrue(
            project.contains(
                "excluding: [\"ButtonHeist/Tests/TheInsideJobTests/**/*IntegrationTests.swift\"]"
            )
        )
        XCTAssertTrue(
            project.contains(
                "\"ButtonHeist/Tests/TheInsideJobTests/**/*IntegrationTests.swift\""
            )
        )
        XCTAssertTrue(project.contains("\"ButtonHeist/Tests/TheInsideJobTests/Helpers/**\""))
    }

    func testCIExecutesEveryHostedTargetWithoutTestSelectors() throws {
        let workflow = try contents(relativePath: ".github/workflows/ci.yml")

        for scheme in [
            "TheInsideJobTests",
            "TheInsideJobIntegrationTests",
            "HostedBehaviorTests",
        ] {
            XCTAssertTrue(workflow.contains("scheme: \(scheme)"), scheme)
        }
        XCTAssertFalse(
            workflow.contains("-skip-testing"),
            "Target membership, not test-name exclusions, must define CI coverage"
        )
        XCTAssertFalse(
            workflow.contains("-only-testing"),
            "Target membership, not test-name selectors, must define CI coverage"
        )
    }

    func testEveryInsideJobIntegrationFileMatchesTheIntegrationTargetConvention() throws {
        let testsDirectory = repositoryRoot()
            .appendingPathComponent("ButtonHeist/Tests/TheInsideJobTests")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: testsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        let integrationFiles = enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent.hasSuffix("IntegrationTests.swift")
        }

        XCTAssertFalse(integrationFiles.isEmpty)
        for file in integrationFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(
                contents.contains("IntegrationTests: XCTestCase"),
                "\(file.lastPathComponent) must expose an integration test class selected by the target glob"
            )
        }
    }

    func testReleaseVerificationRunsEveryCanonicalHostedSuite() throws {
        let releaseScript = try contents(relativePath: "scripts/release.sh")

        for invocation in [
            "run_hosted_release_suite TheInsideJobTests",
            "run_hosted_release_suite TheInsideJobIntegrationTests",
            "run_hosted_release_suite HostedBehaviorTests",
        ] {
            XCTAssertTrue(releaseScript.contains(invocation), invocation)
        }
    }

    func testContributorInstructionsRunEveryCanonicalHostedSuite() throws {
        let instructions = try contents(relativePath: "AGENTS.md")

        for scheme in [
            "TheInsideJobTests",
            "TheInsideJobIntegrationTests",
            "HostedBehaviorTests",
        ] {
            XCTAssertTrue(
                instructions.contains("tuist test \(scheme) --platform ios"),
                scheme
            )
        }
        XCTAssertTrue(instructions.contains("hosted iOS suite has three canonical schemes"))
    }

    private func contents(relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Project.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        XCTFail("Could not locate repository root")
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
