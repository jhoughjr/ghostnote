import Foundation

/// The context engine, which watches the front app and publishes each new context chain to every subscriber (G-05, G-15).
/// One actor owns the current chain and the subscriber map, so no subscriber sees a chain out of order.
/// It publishes a chain only when the chain differs from the one it published last (G-12).
public actor ContextEngine {
    private let source: any FrontAppSource
    private var watchers: [UUID: AsyncStream<ContextChain>.Continuation] = [:]
    private var current: ContextChain?
    private var task: Task<Void, Never>?

    init(source: any FrontAppSource) {
        self.source = source
    }

    /// Starts the watch, and a second call while the watch runs does nothing.
    /// A start after `stop()` reads the source again.
    public func start() {
        guard self.task == nil else { return }
        self.task = Task {
            for await reading in await self.source.readings() {
                self.receive(reading)
            }
        }
    }

    /// Stops the watch and finishes every open subscriber stream.
    /// The current chain stays, so a later `watch()` still starts with it.
    public func stop() {
        self.task?.cancel()
        self.task = nil
        for watcher in self.watchers.values {
            watcher.finish()
        }
        self.watchers = [:]
    }

    /// The chain the engine published last, or nil before the first reading.
    public func currentChain() -> ContextChain? {
        self.current
    }

    func receive(_ reading: FrontReading) {
        let next = ChainBuilder.chain(for: reading)
        guard next != self.current else { return }

        self.current = next
        for watcher in self.watchers.values {
            watcher.yield(next)
        }
    }
}

// MARK: - Subscribers

extension ContextEngine {
    /// A stream of every chain from now on, which starts with the current chain when one exists.
    /// Each call gets its own stream, which ends at `unwatch(_:)`, at `stop()`, or when its reader ends (R-002-08).
    public func watch() -> (UUID, AsyncStream<ContextChain>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ContextChain>.makeStream()
        continuation.onTermination = { _ in
            Task { await self.unwatch(id) }
        }
        if let current = self.current {
            continuation.yield(current)
        }
        self.watchers[id] = continuation
        return (id, stream)
    }

    public func unwatch(_ id: UUID) {
        self.watchers[id]?.finish()
        self.watchers[id] = nil
    }

    /// The number of open subscriber streams, for the tests.
    func watcherCount() -> Int {
        self.watchers.count
    }
}
