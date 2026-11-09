import Testing
@testable import GhostnoteEngine

@Suite("URL key")
struct URLKeyTests {
    @Test(
        "A URL key normalizes a page address",
        arguments: [
            ("HTTPS://Example.COM/Path/", "https://example.com/Path"),
            ("https://example.com/", "https://example.com"),
            ("https://example.com/a#section", "https://example.com/a"),
            ("https://example.com/a?utm_source=x&id=7&fbclid=y", "https://example.com/a?id=7"),
            ("https://example.com/a?UTM_Medium=x", "https://example.com/a"),
            ("https://example.com:8443/a?b=2&a=1", "https://example.com:8443/a?b=2&a=1"),
            ("https://example.com/s?q=a%2Bb", "https://example.com/s?q=a%2Bb"),
            ("https://example.com/a%2F/", "https://example.com/a%2F"),
            ("https://user:pw@Example.com/a", "https://example.com/a"),
        ]
    )
    func normalizes(raw: String, expected: String) {
        #expect(URLKey(raw)?.string == expected)
    }

    @Test(
        "A URL key refuses an address that is not http or https with a host",
        arguments: ["file:///Users/x/a.txt", "about:blank", "ftp://example.com/a", "not a url", "https://"]
    )
    func refuses(raw: String) {
        #expect(URLKey(raw) == nil)
    }
}
