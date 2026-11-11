import Testing
@testable import GhostnoteEngine

@Suite("Chain builder", .timeLimit(.minutes(1)))
struct ChainBuilderTests {
    static let appScope = ContextScope(level: "app", state: .found(.app(bundleID: "com.example.editor")))

    static func reading(trusted: Bool = true, document: String? = nil, url: String? = nil, title: String? = nil) -> FrontReading {
        FrontReading(bundleID: "com.example.editor", trusted: trusted, document: document, url: url, title: title)
    }

    @Test("The app scope comes first and needs no permission")
    func appFirst() {
        #expect(ChainBuilder.chain(for: ChainBuilderTests.reading(trusted: false)).scopes.first == ChainBuilderTests.appScope)
    }

    @Test(
        "The document scope follows the fallback order",
        arguments: [
            (reading(trusted: false, document: "file:///tmp/a.txt"), .noPermission),
            (reading(), .noStrategy),
            (reading(title: ""), .noStrategy),
            (reading(document: "https://example.com/a/", url: "https://other.com", title: "T"), .found(.url(URLKey("https://example.com/a")!))),
            (reading(document: "about:blank", url: "https://other.com/", title: "T"), .found(.url(URLKey("https://other.com")!))),
            (reading(document: "about:blank", url: "about:blank", title: "T"), .found(.title(bundleID: "com.example.editor", title: "T"))),
            (reading(title: "T"), .found(.title(bundleID: "com.example.editor", title: "T"))),
        ] as [(FrontReading, ScopeState)]
    )
    func fallback(reading: FrontReading, expected: ScopeState) {
        #expect(ChainBuilder.chain(for: reading).scopes == [ChainBuilderTests.appScope, ContextScope(level: "document", state: expected)])
    }

    @Test("A file document gives a file key")
    func fileDocument() throws {
        let scope = ChainBuilder.document(for: ChainBuilderTests.reading(document: "file:///usr/./lib", title: "T"))
        #expect(scope.state == .found(.file(try #require(FileKey(.init(fileURLWithPath: "/usr/lib"))))))
    }
}
