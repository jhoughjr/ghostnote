import Foundation
import Testing
@testable import GhostnoteEngine

@Suite("File key")
struct FileKeyTests {
    @Test("A file key removes dot segments")
    func removesDotSegments() {
        let key = FileKey(URL(fileURLWithPath: "/usr/./bin/../lib"))
        #expect(key?.path == "/usr/lib")
    }

    @Test("A file key resolves a symbolic link")
    func resolvesSymlink() throws {
        // given a link in a temporary folder that points at a real file
        let folder = try FileKeyTests.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = try FileKeyTests.makeFile(in: folder, named: "note.txt")
        let link = folder.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        // when both routes become keys, then they are one key
        #expect(FileKey(link) == FileKey(target))
    }

    @Test("A file key gives the on-disk case for a file that exists")
    func onDiskCase() throws {
        let folder = try FileKeyTests.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try FileKeyTests.makeFile(in: folder, named: "Note.txt")

        #expect(FileKey(folder.appendingPathComponent("NOTE.TXT")) == FileKey(file))
    }

    @Test("A file key keeps the standardized path of a file that does not exist")
    func missingFileKept() {
        let name = "/nonexistent-\(UUID().uuidString)"
        let key = FileKey(URL(fileURLWithPath: "\(name)/a/../Note.txt"))
        #expect(key?.path == "\(name)/Note.txt")
    }

    @Test("A file key refuses a URL that is not a file URL")
    func refusesWebURL() throws {
        #expect(FileKey(try #require(URL(string: "https://example.com/a"))) == nil)
    }

    @Test("A file key makes bookmark data that resolves to the same path")
    func bookmarkRoundTrip() throws {
        let folder = try FileKeyTests.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = try #require(FileKey(try FileKeyTests.makeFile(in: folder, named: "note.txt")))

        var stale = false
        let resolved = try URL(resolvingBookmarkData: try key.bookmarkData(), bookmarkDataIsStale: &stale)

        #expect(FileKey(resolved) == key)
    }

    @Test("A file key throws for a missing file")
    func bookmarkMissing() throws {
        let key = try #require(FileKey(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")))
        #expect(throws: (any Error).self) { try key.bookmarkData() }
    }
}

// MARK: - Helpers

extension FileKeyTests {
    /// Makes an empty folder under the temporary directory, which the caller removes.
    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func makeFile(in folder: URL, named name: String) throws -> URL {
        let file = folder.appendingPathComponent(name)
        try Data("a".utf8).write(to: file)
        return file
    }
}
