/// A scope key is the key that a later store matches a note against.
///
/// - app: the identity of the front app (R-002-14).
/// - file: a file, global across apps (G-04).
/// - url: a web page, global across apps (G-04).
/// - title: a window title, which stays under the identity of its app (G-04).
public enum ScopeKey: Sendable, Hashable {
    case app(AppIdentity)
    case file(FileKey)
    case url(URLKey)
    case title(app: AppIdentity, title: String)
}
