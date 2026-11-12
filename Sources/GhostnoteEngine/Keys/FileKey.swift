import Foundation

/// A file key is the normalized path of a file, so that two routes to one file give one key (G-10).
/// The path has its dot segments removed and its symbolic links resolved, and a file that exists gets its on-disk case.
/// Equality uses the path alone, and a store asks for `bookmarkData()` only when it saves a note.
public struct FileKey: Sendable, Hashable {
    public let path: String

    /// Returns nil for a URL that is not a file URL.
    /// A path that does not exist keeps its standardized form, so a file gone from disk can give a second key.
    public init?(_ url: URL) {
        guard url.isFileURL else { return nil }
        self.path = url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Makes macOS bookmark data for the file, which finds it again after a move or a rename.
    /// It throws when the file does not exist.
    public func bookmarkData() throws -> Data {
        try URL(fileURLWithPath: self.path).bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
