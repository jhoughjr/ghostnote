import Testing
@testable import GhostnoteEngine

@Suite("Context engine", .timeLimit(.minutes(1)))
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
        // given a subscriber on an engine over a fake source
        let source = FakeFrontAppSource()
        var reads = source.reads.makeAsyncIterator()
        let engine = ContextEngine(source: source)
        let (_, stream) = await engine.watch()
        var chains = stream.makeAsyncIterator()

        // when the engine starts and the source reports a
        await engine.start()
        await reads.next()
        source.send(ContextEngineTests.reading("com.a"))
        let first = await chains.next()
        await engine.stop()

        // then the subscriber gets a, and the stream ends at the stop
        #expect(first == ContextEngineTests.chain("com.a"))
        #expect(await chains.next() == nil)
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

        // then the engine drops the continuation, through the removal that the stream's end queued
        await Wait.until("the engine keeps the stream of a reader that ended") { await engine.watcherCount() == 0 }
    }

    @Test("A second start reads the source once")
    func startTwice() async {
        let source = FakeFrontAppSource()
        var reads = source.reads.makeAsyncIterator()
        let engine = ContextEngine(source: source)

        await engine.start()
        await engine.start()
        await reads.next()
        await Wait.window(1_000)

        #expect(source.readCount == 1)
        await engine.stop()
    }

    @Test("Stop ends the read, so a later reading changes no chain")
    func stopCancels() async {
        // given a running engine that has published a
        let source = FakeFrontAppSource()
        var reads = source.reads.makeAsyncIterator()
        var ends = source.ends.makeAsyncIterator()
        let engine = ContextEngine(source: source)
        let (_, stream) = await engine.watch()
        var chains = stream.makeAsyncIterator()
        await engine.start()
        await reads.next()
        source.send(ContextEngineTests.reading("com.a"))
        _ = await chains.next()

        // when the engine stops, the source stream ends, and the source sends b
        await engine.stop()
        await ends.next()
        source.send(ContextEngineTests.reading("com.b"))

        // then the current chain is still a
        #expect(await engine.currentChain() == ContextEngineTests.chain("com.a"))
    }

    @Test("A reading in flight at stop changes no chain after stop returns", arguments: 0..<200)
    func stopDropsInFlight(run: Int) async {
        // given a running engine that has published a
        let source = FakeFrontAppSource()
        var reads = source.reads.makeAsyncIterator()
        var ends = source.ends.makeAsyncIterator()
        let engine = ContextEngine(source: source)
        let (_, stream) = await engine.watch()
        var chains = stream.makeAsyncIterator()
        await engine.start()
        await reads.next()
        source.send(ContextEngineTests.reading("com.a"))
        _ = await chains.next()

        // when the source sends b inside the actor call that stops the engine, the source stream ends, and queued work runs
        await engine.stop(inFlight: ContextEngineTests.reading("com.b"), from: source)
        await ends.next()
        await Wait.window(100)

        // then the current chain is still a
        #expect(await engine.currentChain() == ContextEngineTests.chain("com.a"))
    }

    @Test("A start after a stop reads the source again and publishes")
    func startAfterStop() async {
        // given an engine that started and stopped once
        let source = FakeFrontAppSource()
        var reads = source.reads.makeAsyncIterator()
        let engine = ContextEngine(source: source)
        await engine.start()
        await reads.next()
        await engine.stop()

        // when a subscriber watches, the engine starts again, and the source reports b
        let (_, stream) = await engine.watch()
        var chains = stream.makeAsyncIterator()
        await engine.start()
        await reads.next()
        source.send(ContextEngineTests.reading("com.b"))
        let first = await chains.next()
        await engine.stop()

        // then the source was read twice, and the subscriber gets b
        #expect(source.readCount == 2)
        #expect(first == ContextEngineTests.chain("com.b"))
        #expect(await chains.next() == nil)
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
        // given a subscriber that reads in a task
        let engine = ContextEngine(source: FakeFrontAppSource())
        let (_, stream) = await engine.watch()
        let reader = Task {
            for await _ in stream {}
        }

        // when the engine stops, and the time limit's cancel reaches the reader so a missing finish fails and does not hang
        await engine.stop()
        await withTaskCancellationHandler {
            await reader.value
        } onCancel: {
            reader.cancel()
        }

        // then the reader's loop has ended without a cancel
        #expect(reader.isCancelled == false)
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
}

// MARK: - A reading in flight at stop

extension ContextEngine {
    /// Sends a reading through the fake source and stops in one actor call, so the reading is in flight when the read ends.
    func stop(inFlight reading: FrontReading, from source: FakeFrontAppSource) {
        source.send(reading)
        self.stop()
    }
}
