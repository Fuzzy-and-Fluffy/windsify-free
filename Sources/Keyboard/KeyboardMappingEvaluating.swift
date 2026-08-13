import Foundation

/// Pure keyboard-policy boundary shared by the Free event adapter and the
/// private Pro policy. Public Free source contains this contract and the
/// essentials implementation, but not the Pro rule table.
protocol KeyboardMappingEvaluating: Sendable {
    func evaluate(
        _ stroke: KeyboardStroke,
        context: MappingContext
    ) -> RuleDecision

    func contextFreeDecision(
        for stroke: KeyboardStroke
    ) -> RuleDecision?

    func permitsHostShortcut(in context: MappingContext) -> Bool
}

extension KeyboardMappingEvaluating {
    func evaluate(_ stroke: KeyboardStroke) -> RuleDecision {
        evaluate(stroke, context: MappingContext())
    }
}
