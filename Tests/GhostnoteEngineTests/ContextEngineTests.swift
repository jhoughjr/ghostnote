import Synchronization
import Testing
@testable import GhostnoteEngine

@Suite("Context engine")
struct ContextEngineTests {
    static func reading(_ bundleID: String) -> FrontReading {
        FrontReading(bundleID: bundleID, trusted: true, document: nil, url: nil, title: nil)
    }

    static func chain(_ bundleID: String) -> ContextChain {
        ChainBuilder.chain(for: ContextEngineTests.reading(bundleID))
    }

    @Test("A subscriber gets each changed chain once, and a repeat publishes nothing")
    func changeDetection() async {
        // given an engine on a fake source, and one subscriber
        let engine = ContextEngine(source: FakeFrontAppSource())
        let (_, stream) = await engine.watch()

        // when the source reports a, a again, then b
        await engine.receive(ContextEngineTests.reading("com.a"))
        await engine.receive(ContextEngineTests.reading("com.a"))
        await engine.receive(ContextEngineTests.reading("com.b"))
        await engine.stop()

        // then the subscriber sees a and b, once each
        #expect(await ContextEngineTests.drain(stream) == [ContextEngineTests.chain("com.a"), ContextEngineTests.chain("com.b")])
    }

    @Test("A late subscriber gets the current chain first")
    func currentFirst() async {
        let engine = ContextEngine(source: FakeFrontAppSource())
        await engine.receive(ContextEngineTests.reading("com.a"))

        let (_, stream) = await engine.watch()
        await engine.stop()

        #expect(await ContextEngineTests.drain(stream) == [ContextEngineTests.chain("com.a")])
    }

    @Test("Every subscriber gets every chain")
    func fanOut() async {
        let engine = ContextEngine(source: FakeFrontAppSource())
        let (_, first) = await engine.watch()
        let (_, second) = await engine.watch()

        await engine.receive(ContextEngineTests.reading("com.a"))
        await engine.stop()

        #expect(await ContextEngineTests.drain(first) == [ContextEngineTests.chain("com.a")])
        #expect(await ContextEngineTests.drain(second) == [ContextEngineTests.chain("com.a")])
    }

    @Test("Unwatch finishes that stream alone")
    func unwatch() async {
        let engine = ContextEngine(source: FakeFrontAppSource())
        let (id, first) = await engine.watch()
        let (_, second) = await engine.watch()

        await engine.unwatch(id)
        await engine.receive(ContextEngineTests.reading("com.a"))
        await engine.stop()

        #expect(await ContextEngineTests.drain(first).isEmpty)
        #expect(await ContextEngineTests.drain(second).count == 1)
    }

    @Test("Start reads the source")
    func startReadsSource() async {
        let source = FakeFrontAppSource()
        let engine = ContextEngine(source: source)
        let (_, stream) = await engine.watch()
        await engine.start()
        await ContextEngineTests.settle { source.readCount > 0 }

        source.send(ContextEngineTests.reading("com.a"))
        await ContextEngineTests.settle { await engine.currentChain() != nil }
        await engine.stop()

        #expect(await ContextEngineTests.drain(stream) == [ContextEngineTests.chain("com.a")])
    }

    @Test("A subscriber that stops reading leaves the map")
    func terminationRemoves() async {
        // given one subscriber that reads in a task
        let engine = ContextEngine(source: FakeFrontAppSource())
        let (_, stream) = await engine.watch()
        let reader = Task {
            for await _ in stream {}
        }

        // when the task ends
        reader.cancel()
        await reader.value

        // then the engine drops the continuation
        await ContextEngineTests.settle { await engine.watcherCount() == 0 }
        #expect(await engine.watcherCount() == 0)
    }

    @Test("A second start reads the source once")
    func startTwice() async {
        let source = FakeFrontAppSource()
        let engine = ContextEngine(source: source)

        await engine.start()
        await engine.start()
        await ContextEngineTests.settle { source.readCount > 1 }

        #expect(source.readCount == 1)
        await engine.stop()
    }

    @Test("Stop ends the read, so a later reading changes no chain")
    func stopCancels() async {
        // given a running engine that has published a
        let source = FakeFrontAppSource()
        let engine = ContextEngine(source: source)
        await engine.start()
        await ContextEngineTests.settle { source.readCount > 0 }
        source.send(ContextEngineTests.reading("com.a"))
        await ContextEngineTests.settle { await engine.currentChain() != nil }

        // when the engine stops and the source sends b
        await engine.stop()
        source.send(ContextEngineTests.reading("com.b"))
        await ContextEngineTests.settle { await engine.currentChain() != ContextEngineTests.chain("com.a") }

        // then the current chain is still a
        #expect(await engine.currentChain() == ContextEngineTests.chain("com.a"))
    }

    @Test("A start after a stop reads the source again and publishes")
    func startAfterStop() async {
        let source = FakeFrontAppSource()
        let engine = ContextEngine(source: source)
        await engine.start()
        await ContextEngineTests.settle { source.readCount > 0 }
        await engine.stop()

        let (_, stream) = await engine.watch()
        await engine.start()
        await ContextEngineTests.settle { source.readCount > 1 }
        source.send(ContextEngineTests.reading("com.b"))
        await ContextEngineTests.settle { await engine.currentChain() != nil }
        await engine.stop()

        #expect(source.readCount == 2)
        #expect(await ContextEngineTests.drain(stream) == [ContextEngineTests.chain("com.b")])
    }

    @Test("A watch after a stop stays open and starts with the current chain")
    func watchAfterStop() async {
        let engine = ContextEngine(source: FakeFrontAppSource())
        await engine.receive(ContextEngineTests.reading("com.a"))
        await engine.stop()

        let (_, stream) = await engine.watch()
        #expect(await engine.watcherCount() == 1)
        await engine.stop()

        #expect(await ContextEngineTests.drain(stream) == [ContextEngineTests.chain("com.a")])
    }

    @Test("Stop finishes every open stream")
    func stopFinishes() async {
        // given a subscriber that reads in a task and marks its end
        let engine = ContextEngine(source: FakeFrontAppSource())
        let (_, stream) = await engine.watch()
        let ended = Mutex(false)
        let reader = Task {
            for await _ in stream {}
            ended.withLock { $0 = true }
        }

        // when the engine stops
        await engine.stop()
        await ContextEngineTests.settle { ended.withLock { $0 } }

        // then the reader's loop has ended without a cancel
        #expect(ended.withLock { $0 })
        reader.cancel()
    }
}

// MARK: - Helpers

extension ContextEngineTests {
    /// Reads a stream to its end, which comes because every caller stops the engine first.
    static func drain(_ stream: AsyncStream<ContextChain>) async -> [ContextChain] {
        var seen: [ContextChain] = []
        for await chain in stream {
            seen.append(chain)
        }
        return seen
    }

    /// Yields until the condition holds, or 100 times, so a task the engine started gets to run.
    static func settle(until condition: () async -> Bool) async {
        for _ in 0..<100 {
            guard await condition() == false else { return }
            await Task.yield()
        }
    }
}
