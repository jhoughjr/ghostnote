/// A scope key is the key that a later store matches a note against.
///
/// - app: the bundle identifier of the front app.
/// - file: a file, global across apps (G-04).
/// - url: a web page, global across apps (G-04).
/// - title: a window title, which stays under its app (G-04).
public enum ScopeKey: Sendable, Hashable {
    case app(bundleID: String)
    case file(FileKey)
    case url(URLKey)
    case title(bundleID: String, title: String)
}
