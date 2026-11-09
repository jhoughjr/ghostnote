/// What the engine found at one scope (G-08).
///
/// - found: a strategy found the scope, and the key names it.
/// - noPermission: the strategy needs a grant that the user has not given.
/// - noStrategy: no strategy found anything at this scope.
public enum ScopeState: Sendable, Hashable {
    case found(ScopeKey)
    case noPermission
    case noStrategy
}
