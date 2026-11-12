import Foundation

/// A URL key is the normalized form of a web page address, so that two visits to one page give one key (G-11).
/// It removes the fragment, the tracking parameters, every trailing slash, the user and the password, and it lowercases the scheme and the host.
/// It keeps the port, the path case, the percent-encoding and the order of the other parameters as given.
public struct URLKey: Sendable, Hashable {
    /// These query names only track a visit and never select a page.
    /// A name that starts with `utm_` is also a tracking name, see `isTracking(_:)`.
    static let trackingNames: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid"]

    public let string: String

    /// Returns nil for a string that is not an http or https address with a host.
    public init?(_ raw: String) {
        guard var parts = URLComponents(string: raw) else { return nil }
        guard let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = parts.host, host.isEmpty == false else { return nil }

        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.user = nil
        parts.password = nil
        parts.fragment = nil

        // The encoded forms keep `%2B` and `%2F` as given, because a decoded `+` or `/` names another page.
        let kept = (parts.percentEncodedQueryItems ?? []).filter { URLKey.isTracking($0.name) == false }
        parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        while parts.percentEncodedPath.hasSuffix("/") {
            parts.percentEncodedPath.removeLast()
        }

        guard let string = parts.string else { return nil }
        self.string = string
    }

    static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || URLKey.trackingNames.contains(lower)
    }
}
