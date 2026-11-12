import Testing

/// Waits for a condition that no event marks, such as work that an actor or the main actor has queued.
/// A positive wait records an issue when its bound runs out, so the test fails at the wait and names its cause (A-1).
/// It is the one home of a yield loop in the tests, and a test awaits an event wherever one exists.
enum Wait {
    /// The most yields that a positive wait takes.
    /// A wait that needs more on a loaded pool is a sign that the test needs an event.
    static let bound = 10_000

    /// Yields until the condition holds, and records an issue when the bound runs out first.
    /// It runs on the caller's actor, so a main actor test can wait on main actor state.
    static func until(
        _ comment: Comment,
        isolation: isolated (any Actor)? = #isolation,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () async -> Bool
    ) async {
        guard await Wait.yields(Wait.bound, isolation: isolation, until: condition) == false else { return } // The condition held in time.
        Issue.record(comment, sourceLocation: sourceLocation)
    }

    /// Yields the given number of times, so that a wrong event already queued can happen before an absence check.
    static func window(_ count: Int, isolation: isolated (any Actor)? = #isolation) async {
        _ = await Wait.yields(count, isolation: isolation) { false }
    }

    private static func yields(
        _ count: Int,
        isolation: isolated (any Actor)?,
        until condition: () async -> Bool
    ) async -> Bool {
        for _ in 0..<count {
            guard await condition() == false else { return true }
            await Task.yield()
        }
        return await condition()
    }
}
