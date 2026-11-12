import AppKit
import Testing
@testable import GhostnoteEngine

/// Runs against the real front app, so it needs a Mac session with the Accessibility grant and stays off unless GHOSTNOTE_LIVE is 1.
@Suite(
    "Live engine",
    .enabled(if: ProcessInfo.processInfo.environment["GHOSTNOTE_LIVE"] == "1"),
    .timeLimit(.minutes(1))
)
struct LiveEngineTests {
    @Test("The live engine publishes the front app first")
    func firstChain() async throws {
        let engine = ContextEngine()
        let (_, stream) = await engine.watch()
        await engine.start()

        var iterator = stream.makeAsyncIterator()
        let first = try #require(await iterator.next())
        print("live chain: \(first)")
        #expect(first.scopes.first?.level == "app")
        await engine.stop()
    }

    @Test("The end of the stream removes both observers and the run loop source")
    @MainActor
    func stopReleasesObservers() async throws {
        // given a live source with a reader, whose observer delivers in the common modes
        let source = LiveFrontAppSource()
        let stream = source.readings()
        let reader = Task {
            for await _ in stream {}
        }
        #expect(source.activation != nil)
        let loopSource = AXObserverGetRunLoopSource(try #require(source.observer))
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), loopSource, .commonModes))

        // when the reader ends, as the engine's stop ends it
        reader.cancel()
        await reader.value
        await Wait.until("the queued teardown leaves the activation observer") { source.activation == nil }

        // then nothing stays registered, and the run loop holds the source in no mode
        #expect(source.observer == nil)
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), loopSource, .commonModes) == false)
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), loopSource, .defaultMode) == false)
    }

    @Test("A teardown that a dropped stream queued leaves the newer stream's observers", arguments: 0..<200)
    @MainActor
    func staleTeardownKeeps(run: Int) async {
        // given a first stream dropped at once, so its end queues a teardown, and a second read
        let source = LiveFrontAppSource()
        _ = source.readings()
        let stream = source.readings()

        // when the queued main actor work runs
        await Wait.window(10)

        // then the second read keeps both observers
        #expect(source.activation != nil)
        #expect(source.observer != nil)
        withExtendedLifetime(stream) {}
        source.tearDown()
    }

    @Test("An observer that observe(pid:) replaces leaves the run loop")
    @MainActor
    func replacedObserverLeaves() throws {
        // given a live source observing the front app
        let source = LiveFrontAppSource()
        let stream = source.readings()
        let loopSource = AXObserverGetRunLoopSource(try #require(source.observer))
        let front = try #require(NSWorkspace.shared.frontmostApplication)

        // when the source observes the front app again
        source.observe(pid: front.processIdentifier)

        // then the first observer's source is in no mode of the main run loop
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), loopSource, .commonModes) == false)
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), loopSource, .defaultMode) == false)
        withExtendedLifetime(stream) {}
        source.tearDown()
    }

    @Test("A process that refuses every registration gets no observer")
    @MainActor
    func refusedKeepsNoObserver() {
        // given the test process itself, which refuses both AX notifications
        let source = LiveFrontAppSource()

        // when the source observes it
        source.observe(pid: ProcessInfo.processInfo.processIdentifier)

        // then no observer counts as installed, so the next activation tries again
        #expect(source.observer == nil)
    }
}
