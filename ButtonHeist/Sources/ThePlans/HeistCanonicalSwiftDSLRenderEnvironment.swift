import Foundation

struct RenderEnvironment {
    static let empty = RenderEnvironment()

    var targetReferences: Set<HeistReferenceName> = []
    var stringReferences: Set<HeistReferenceName> = []

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
        case .elementTarget:
            return bindingTargetReference(name)
        }
    }
}
