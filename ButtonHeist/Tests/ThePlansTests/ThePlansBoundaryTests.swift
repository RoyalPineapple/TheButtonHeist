import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test func `artifact format has one canonical wire spelling`() throws {
    let encoded = try JSONEncoder().encode(HeistArtifactFormat.buttonHeist)

    #expect(HeistArtifactFormat.allCases == [.buttonHeist])
    #expect(String(bytes: encoded, encoding: .utf8) == #""com.royalpineapple.buttonheist.heist""#)
}

@Test func `artifact producer name is typed open vocabulary metadata`() throws {
    let producer = HeistArtifactProducer(name: "third-party-compiler", version: "4.2")
    let encoded = try JSONEncoder().encode(producer)
    let decoded = try JSONDecoder().decode(HeistArtifactProducer.self, from: encoded)

    #expect(decoded == producer)
    #expect(decoded.name.description == "third-party-compiler")
    #expect(decoded.version?.description == "4.2")
}

@Test func `artifact producer values reject blank construction and decoding`() throws {
    #expect(throws: HeistArtifactProducerName.ValidationError.self) {
        try HeistArtifactProducerName(validating: " \n\t")
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HeistArtifactProducerName.self, from: Data(#"" \n\t""#.utf8))
    }
    #expect(throws: HeistArtifactProducerVersion.ValidationError.self) {
        try HeistArtifactProducerVersion(validating: " \n\t")
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HeistArtifactProducerVersion.self, from: Data(#"" \n\t""#.utf8))
    }
}

@Test
func `representative heist plan encodes decodes validates and renders`() throws {
    let plan = try HeistPlan("loginFlow") {
        TypeText("alex@example.com", into: .identifier("email"))
            .expect(.exists(.value("alex@example.com")), timeout: 1)

        Activate(.label("Submit"))
            .expect(.changed(.screen()))
            .expect(.exists(.label("Home")), timeout: 5)

        WaitFor(.missing(.label("Loading")), timeout: 1)

        If {
            Case(.exists(.label("Promo"))) {
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
    #expect(decoded.lint(.strictTest).isEmpty)

    let rendered = try decoded.canonicalSwiftDSL()
    #expect(rendered.contains(#"HeistPlan("loginFlow")"#))
    #expect(rendered.contains(#"TypeText("alex@example.com", into: .identifier("email"))"#))
    #expect(rendered.contains(#"Activate(.label("Submit"))"#))
}
