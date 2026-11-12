import Foundation

/// An app identity names the app that a scope sits under, so an app with no bundle identifier still gets an app scope (R-002-13).
/// The bundle identifier is used when one exists, and the path only when none does (R-002-14).
///
/// - bundleID: the bundle identifier of the app.
/// - path: the path of the app bundle, or of the executable for an app with no bundle, normalized by the file key rules (R-002-04).
public enum AppIdentity: Sendable, Hashable {
    case bundleID(String)
    case path(String)
}

// MARK: - The identity of a running app

extension AppIdentity {
    /// Takes the bundle identifier when one exists, else the file key path of the app's URL, and gives nil when neither exists.
    init?(bundleID: String?, appURL: URL?) {
        if let bundleID {
            self = .bundleID(bundleID)
        } else if let appURL, let key = FileKey(appURL) {
            self = .path(key.path)
        } else {
            return nil
        }
    }
}
