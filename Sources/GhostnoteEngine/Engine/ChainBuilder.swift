import Foundation

/// Builds a chain from one reading, with the default strategy order that applies when no manifest exists (G-06).
enum ChainBuilder {
    static func chain(for reading: FrontReading) -> ContextChain {
        let app = ContextScope(level: "app", state: .found(.app(bundleID: reading.bundleID)))
        return ContextChain(scopes: [app, ChainBuilder.document(for: reading)])
    }

    /// Tries AXDocument, then AXURL, then the window title, and takes the first that gives a key.
    static func document(for reading: FrontReading) -> ContextScope {
        guard reading.trusted else { return ContextScope(level: "document", state: .noPermission) }

        let candidates: [ScopeKey?] = [
            reading.document.flatMap(ChainBuilder.key(forAddress:)),
            reading.url.flatMap(ChainBuilder.key(forAddress:)),
            reading.title.flatMap { $0.isEmpty ? nil : ScopeKey.title(bundleID: reading.bundleID, title: $0) },
        ]
        guard let key = candidates.compactMap({ $0 }).first else { return ContextScope(level: "document", state: .noStrategy) }
        return ContextScope(level: "document", state: .found(key))
    }

    /// A file URL gives a file key, an http or https URL gives a URL key, and any other address gives nil.
    static func key(forAddress address: String) -> ScopeKey? {
        if let url = URL(string: address), url.isFileURL, let file = FileKey(url) {
            return .file(file)
        }
        if let page = URLKey(address) {
            return .url(page)
        }
        return nil
    }
}
