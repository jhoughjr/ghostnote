import Synchronization
@testable import GhostnoteEngine

/// A test drives this front-app source by hand, in place of NSWorkspace and the Accessibility API.
/// Each read gets a fresh stream, as the live source does, and `send(_:)` goes to the newest one.
/// It signals each read on `reads` and the end of each stream on `ends`, so a test awaits an event and never counts yields (A-1).
final class FakeFrontAppSource: FrontAppSource {
    let reads: AsyncStream<Void>
    let ends: AsyncStream<Void>
    private let readSignal: AsyncStream<Void>.Continuation
    private let endSignal: AsyncStream<Void>.Continuation
    private let continuations = Mutex<[AsyncStream<FrontReading>.Continuation]>([])

    /// Counts the times the engine has read the source.
    var readCount: Int {
        self.continuations.withLock { $0.count }
    }

    init() {
        (self.reads, self.readSignal) = AsyncStream<Void>.makeStream()
        (self.ends, self.endSignal) = AsyncStream<Void>.makeStream()
    }

    func readings() async -> AsyncStream<FrontReading> {
        let (stream, continuation) = AsyncStream<FrontReading>.makeStream()
        let ended = self.endSignal
        continuation.onTermination = { _ in
            ended.yield()
        }
        self.continuations.withLock { $0.append(continuation) }
        self.readSignal.yield()
        return stream
    }

    func send(_ reading: FrontReading) {
        self.continuations.withLock { _ = $0.last?.yield(reading) }
    }
}
