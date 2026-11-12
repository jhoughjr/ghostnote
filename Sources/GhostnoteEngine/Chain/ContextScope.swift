/// A scope is one level of a context chain, with a level label and the state the engine found at that level.
/// The label is free text, because a later manifest names its own levels and the engine does not interpret them (R-002-02).
public struct ContextScope: Sendable, Hashable {
    public let level: String
    public let state: ScopeState

    public init(level: String, state: ScopeState) {
        self.level = level
        self.state = state
    }
}
