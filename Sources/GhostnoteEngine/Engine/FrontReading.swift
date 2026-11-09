/// What the platform reports about the front app at one moment, before the engine builds a chain from it.
/// The live source fills it from NSWorkspace and the Accessibility API, and a test fills it by hand.
struct FrontReading: Sendable, Hashable {
    var bundleID: String
    var trusted: Bool
    var document: String?
    var url: String?
    var title: String?
}
