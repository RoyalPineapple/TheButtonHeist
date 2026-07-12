import ThePlans

func literalTarget(
    _ predicate: ElementPredicate,
    ordinal: Int? = nil
) -> AccessibilityTarget {
    .predicate(ElementPredicateTemplate(predicate), ordinal: ordinal)
}
