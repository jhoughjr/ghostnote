/// A chain holds the context of the front app at one moment, as scopes from wide to narrow.
/// The engine stores the chain and does not interpret the levels (G-03).
/// The first scope is always the app scope, which needs no permission.
public struct ContextChain: Sendable, Hashable {
    public let scopes: [ContextScope]

    public init(scopes: [ContextScope]) {
        self.scopes = scopes
    }
}
