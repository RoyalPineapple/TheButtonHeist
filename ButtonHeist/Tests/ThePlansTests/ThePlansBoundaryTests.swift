import Foundation
import Testing
import ThePlans

@Test
func `representative heist plan encodes decodes validates and renders`() throws {
    let plan = try HeistPlan("loginFlow") {
        TypeText("alex@example.com", into: .identifier("email"))
            .expect(.present(.value("alex@example.com")), timeout: .seconds(1))

        Activate(.label("Submit"))
            .expect(.changed(.screen()))
            .expect(.present(.label("Home")), timeout: .seconds(5))

        WaitFor(.absent(.label("Loading")), timeout: .seconds(1))

        If {
            Case(.present(.label("Promo"))) {
                Warn("promo visible")
            }

            Else {
                Warn("promo skipped")
            }
        }
    }

    let data = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

    #expect(decoded == plan)
    #expect(decoded.runtimeAdmissionFailures().isEmpty)
    #expect(decoded.lint(.strictTest).isEmpty)

    let rendered = try decoded.canonicalSwiftDSL()
    #expect(rendered.contains(#"try HeistPlan("loginFlow")"#))
    #expect(rendered.contains(#"TypeText("alex@example.com", into: .identifier("email"))"#))
    #expect(rendered.contains(#"Activate(.label("Submit"))"#))
}

@Test
func `thePlans does not import runtime or adapter modules`() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sources = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ThePlans")
    let forbiddenImports = [
        "TheFence",
        "TheInsideJob",
        "ButtonHeist",
        "ButtonHeistCLI",
        "ButtonHeistMCP",
        "TheScore",
        "MCP",
        "ArgumentParser",
        "AccessibilitySnapshotModel",
    ]

    let files = try FileManager.default
        .contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }

    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        for forbiddenImport in forbiddenImports {
            #expect(!source.contains("import \(forbiddenImport)"), "\(file.lastPathComponent) imports \(forbiddenImport)")
        }
    }
}
