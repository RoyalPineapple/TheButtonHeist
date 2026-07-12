import Foundation

// Admission owns the externally submitted plan shape. Decoding this type proves
// only that source/artifact JSON can be loaded as plan IR; runtime safety is the
// separate executable-plan boundary.
package struct HeistPlanAdmissionCandidate: Codable, Sendable, Equatable {
    package let version: Int
    package let name: String?
    package let parameter: HeistParameter
    package let definitions: [HeistPlanAdmissionCandidate]
    package let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, name, parameter, definitions, body
    }

    package init(
        version: Int = HeistPlan.currentVersion,
        name: String? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlanAdmissionCandidate] = [],
        body: [HeistStepAdmissionCandidate]
    ) {
        self.version = version
        self.name = name
        self.parameter = parameter
        self.definitions = definitions
        self.body = body
    }

    init(_ plan: HeistPlan) {
        version = plan.version
        name = plan.name
        parameter = plan.parameter
        definitions = plan.definitions.map(HeistPlanAdmissionCandidate.init)
        body = plan.body.map(HeistStepAdmissionCandidate.init)
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == HeistPlan.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported heist plan version \(decodedVersion). " +
                    "This Button Heist build supports version \(HeistPlan.currentVersion)."
            )
        }
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan")
        version = decodedVersion
        name = try container.decodeIfPresent(String.self, forKey: .name)
        parameter = try container.decodeIfPresent(HeistParameter.self, forKey: .parameter) ?? .none
        definitions = try container.decodeIfPresent([HeistPlanAdmissionCandidate].self, forKey: .definitions) ?? []
        body = try container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        guard !body.isEmpty || !definitions.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .body,
                in: container,
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(name, forKey: .name)
        if parameter != .none {
            try container.encode(parameter, forKey: .parameter)
        }
        if !definitions.isEmpty {
            try container.encode(definitions, forKey: .definitions)
        }
        try container.encode(body, forKey: .body)
    }

    func runtimeSafetyPlan() -> HeistPlan {
        HeistPlan(
            runtimeValidatedVersion: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map { $0.runtimeSafetyPlan() },
            body: body.map(\.runtimeSafetyStep)
        )
    }
}

package struct HeistStepAdmissionCandidate: Codable, Sendable, Equatable {
    private typealias Payload = HeistStepWirePayload<HeistPlanAdmissionCandidate>

    private let payload: Payload

    private init(_ payload: Payload) {
        self.payload = payload
    }

    init(_ step: HeistStep) {
        switch step {
        case .action(let step): self.init(Payload.action(step))
        case .wait(let step): self.init(Payload.wait(step))
        case .conditional(let step): self.init(Payload.conditional(step))
        case .forEachElement(let step): self.init(Payload.forEachElement(step))
        case .forEachString(let step): self.init(Payload.forEachString(step))
        case .repeatUntil(let step): self.init(Payload.repeatUntil(step))
        case .warn(let step): self.init(Payload.warn(step))
        case .fail(let step): self.init(Payload.fail(step))
        case .heist(let plan): self.init(Payload.heist(HeistPlanAdmissionCandidate(plan)))
        case .invoke(let step): self.init(Payload.invoke(step))
        }
    }

    package static func action(_ step: ActionStep) -> Self { Self(Payload.action(step)) }
    package static func wait(_ step: WaitStep) -> Self { Self(Payload.wait(step)) }
    package static func conditional(_ step: ConditionalStep) -> Self { Self(Payload.conditional(step)) }
    package static func forEachElement(_ step: ForEachElementStep) -> Self { Self(Payload.forEachElement(step)) }
    package static func forEachString(_ step: ForEachStringStep) -> Self { Self(Payload.forEachString(step)) }
    package static func repeatUntil(_ step: RepeatUntilStep) -> Self { Self(Payload.repeatUntil(step)) }
    package static func warn(_ step: WarnStep) -> Self { Self(Payload.warn(step)) }
    package static func fail(_ step: FailStep) -> Self { Self(Payload.fail(step)) }
    package static func heist(_ plan: HeistPlanAdmissionCandidate) -> Self { Self(Payload.heist(plan)) }
    package static func invoke(_ step: HeistInvocationStep) -> Self { Self(Payload.invoke(step)) }

    var runtimeSafetyStep: HeistStep {
        switch payload {
        case .action(let step): return .action(step)
        case .wait(let step): return .wait(step)
        case .conditional(let step): return .conditional(step)
        case .forEachElement(let step): return .forEachElement(step)
        case .forEachString(let step): return .forEachString(step)
        case .repeatUntil(let step): return .repeatUntil(step)
        case .warn(let step): return .warn(step)
        case .fail(let step): return .fail(step)
        case .heist(let plan): return .heist(plan.runtimeSafetyPlan())
        case .invoke(let step): return .invoke(step)
        }
    }

    package init(from decoder: Decoder) throws {
        payload = try Payload(from: decoder)
    }

    package func encode(to encoder: Encoder) throws {
        try payload.encode(to: encoder)
    }
}
