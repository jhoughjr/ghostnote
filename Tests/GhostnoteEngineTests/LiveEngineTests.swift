import Foundation
import Testing
@testable import GhostnoteEngine

/// Runs against the real front app, so it needs a Mac session with the Accessibility grant and stays off unless GHOSTNOTE_LIVE is 1.
@Suite("Live engine", .enabled(if: ProcessInfo.processInfo.environment["GHOSTNOTE_LIVE"] == "1"))
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

    @Test("The end of the stream removes both observers")
    @MainActor
    func stopReleasesObservers() async {
        // given a live source with a reader
        let source = LiveFrontAppSource()
        let stream = source.readings()
        let reader = Task {
            for await _ in stream {}
        }
        #expect(source.activation != nil)
        #expect(source.observer != nil)

        // when the reader ends, as the engine's stop ends it
        reader.cancel()
        await reader.value
        for _ in 0..<100 where source.activation != nil {
            await Task.yield()
        }

        // then nothing stays registered
        #expect(source.activation == nil)
        #expect(source.observer == nil)
    }
}
