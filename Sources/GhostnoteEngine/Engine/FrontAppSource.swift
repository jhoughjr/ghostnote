/// A front-app source is the platform side of the engine, and it watches the front app and reports a reading at each change (G-14).
/// The engine reads only through this protocol, so a test drives the engine with no Accessibility grant (R-002-06).
protocol FrontAppSource: Sendable {
    /// Returns every reading after the call: one at the start, and one at each app activation, focused-window change and title change.
    func readings() async -> AsyncStream<FrontReading>
}
