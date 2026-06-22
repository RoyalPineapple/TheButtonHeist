#if canImport(UIKit)
import AccessibilitySnapshotModel
import ThePlans
import TheScore

extension AccessibilityContainer {
    var typeName: ContainerTypeName {
        switch type {
        case .semanticGroup:
            return .semanticGroup
        case .list:
            return .list
        case .landmark:
            return .landmark
        case .dataTable:
            return .dataTable
        case .tabBar:
            return .tabBar
        case .scrollable:
            return .scrollable
        }
    }

    var containerLabel: String? {
        if case .semanticGroup(let label, _, _) = type { return label }
        return nil
    }

    var containerValue: String? {
        if case .semanticGroup(_, let value, _) = type { return value }
        return nil
    }

    var containerIdentifier: String? {
        if case .semanticGroup(_, _, let identifier) = type { return identifier }
        return nil
    }

    func matches(_ matcher: ContainerMatcher, annotation: InterfaceContainerAnnotation?) -> Bool {
        if let containerName = matcher.containerName {
            if containerName.isEmpty { return false }
            guard annotation?.containerName == containerName else { return false }
        }
        if let type = matcher.type {
            guard typeName == type else { return false }
        }
        if let label = matcher.label {
            if label.isEmpty { return false }
            guard ElementPredicate.stringEquals(containerLabel ?? "", label) else { return false }
        }
        if let value = matcher.value {
            if value.isEmpty { return false }
            guard ElementPredicate.stringEquals(containerValue ?? "", value) else { return false }
        }
        if let identifier = matcher.identifier {
            if identifier.isEmpty { return false }
            guard ElementPredicate.stringEquals(containerIdentifier ?? "", identifier) else { return false }
        }
        if let isModalBoundary = matcher.isModalBoundary {
            guard self.isModalBoundary == isModalBoundary else { return false }
        }
        return true
    }
}

#endif // canImport(UIKit)
