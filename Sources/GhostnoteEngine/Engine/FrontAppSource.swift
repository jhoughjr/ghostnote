/// The platform side of the engine, which watches the front app and reports a reading at each change (G-14).
/// The engine reads only through this protocol, so a test drives the engine with no Accessibility grant (R-002-06).
protocol FrontAppSource: Sendable {
    /// Every reading from now on: one at the start, and one at each app activation, focused-window change and title change.
    func readings() async -> AsyncStream<FrontReading>
}
