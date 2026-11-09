import Synchronization
@testable import GhostnoteEngine

/// A test drives this front-app source by hand, in place of NSWorkspace and the Accessibility API.
/// Each read gets a fresh stream, as the live source does, and `send(_:)` goes to the newest one.
final class FakeFrontAppSource: FrontAppSource {
    private let continuations = Mutex<[AsyncStream<FrontReading>.Continuation]>([])

    /// Counts the times the engine has read the source.
    var readCount: Int {
        self.continuations.withLock { $0.count }
    }

    func readings() async -> AsyncStream<FrontReading> {
        let (stream, continuation) = AsyncStream<FrontReading>.makeStream()
        self.continuations.withLock { $0.append(continuation) }
        return stream
    }

    func send(_ reading: FrontReading) {
        self.continuations.withLock { _ = $0.last?.yield(reading) }
    }
}
