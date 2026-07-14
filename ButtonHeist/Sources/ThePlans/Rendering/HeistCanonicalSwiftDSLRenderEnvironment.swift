import Foundation

struct RenderEnvironment {
    static let empty = RenderEnvironment()
    static let preservingReferences = RenderEnvironment(referencePolicy: .preserve)

    var targetReferences: Set<HeistReferenceName> = []
    var stringReferences: Set<HeistReferenceName> = []
    private let referencePolicy: ReferencePolicy

    private enum ReferencePolicy {
        case validate
        case preserve
    }

    private init(referencePolicy: ReferencePolicy = .validate) {
        self.referencePolicy = referencePolicy
    }

    init(scope: HeistReferenceScope) {
        targetReferences = scope.targetRefs
        stringReferences = scope.stringRefs
        referencePolicy = .validate
    }

    func accepts(target reference: HeistReferenceName) -> Bool {
        referencePolicy == .preserve || targetReferences.contains(reference)
    }

    func accepts(string reference: HeistReferenceName) -> Bool {
        referencePolicy == .preserve || stringReferences.contains(reference)
    }

    func bindingTargetReference(_ reference: HeistReferenceName) -> RenderEnvironment {
        var copy = self
        copy.targetReferences.insert(reference)
        return copy
    }

    func bindingStringReference(_ reference: HeistReferenceName) -> RenderEnvironment {
        var copy = self
        copy.stringReferences.insert(reference)
        return copy
    }

    func binding(parameter: HeistParameter) throws -> RenderEnvironment {
        guard let name = parameter.name else { return self }
        switch parameter {
        case .none:
            return self
        case .string:
            return bindingStringReference(name)
        case .accessibilityTarget:
            return bindingTargetReference(name)
        }
    }
}
