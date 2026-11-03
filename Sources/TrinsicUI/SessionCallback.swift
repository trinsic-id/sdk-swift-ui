import AuthenticationServices
import Foundation

/// The address to capture when a browser session finishes. Full URLs are matched
/// by scheme, host and path; result query parameters are supplied by Trinsic.
internal struct SessionCallback {
    let scheme: String
    let host: String?
    let path: String?
    private let nativePath: String?

    init(customScheme: String) throws {
        guard !customScheme.isEmpty else {
            throw TrinsicError.error(with: .emptyCallbacklUrl)
        }
        guard customScheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil,
              !["http", "https"].contains(customScheme.lowercased()) else {
            throw TrinsicError.error(with: .unparsableCallbackUrl,
                message: "Supply a custom scheme, or use callbackUrl with a complete HTTPS URL.")
        }
        scheme = customScheme.lowercased()
        host = nil
        path = nil
        nativePath = nil
    }

    init(url: String) throws {
        guard !url.isEmpty else {
            throw TrinsicError.error(with: .emptyCallbacklUrl)
        }
        guard url.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              scheme != "http",
              let parsedUrl = components.url,
              components.user == nil, components.password == nil,
              components.port == nil, components.query == nil, components.fragment == nil,
              scheme != "https" || !(parsedUrl.host ?? "").isEmpty,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath.hasPrefix("/") else {
            throw TrinsicError.error(with: .unparsableCallbackUrl,
                message: "Use an absolute HTTPS or custom-scheme callback URL without credentials, a port, query or fragment.")
        }
        self.scheme = scheme
        // URL.host preserves the ASCII (IDNA) form required by Apple's matcher.
        host = parsedUrl.host?.lowercased()
        path = scheme == "https" && components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        // Apple matches decoded paths; retain the encoded path above for exact result validation.
        nativePath = scheme == "https" && components.path.isEmpty ? "/" : components.path
    }

    func matches(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else { return false }
        // Preserve the original scheme-only API's matching behavior.
        guard let path = path else { return true }
        let actualPath = scheme == "https" && components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return url.host?.lowercased() == host && actualPath == path
            && components.user == nil && components.password == nil
            && components.port == nil && components.fragment == nil
    }

    func matchesResult(_ url: URL, sessionId: String?) -> Bool {
        let ids = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "sessionId" } ?? []
        return matches(url) && sessionId != nil && ids.count == 1 && ids[0].value == sessionId
    }

    @available(iOS 13.0, macOS 14.4, *)
    func makeSession(url: URL, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) throws -> ASWebAuthenticationSession {
        if #available(iOS 17.4, macOS 14.4, *) {
            return ASWebAuthenticationSession(url: url, callback: nativeCallback, completionHandler: completionHandler)
        }
        guard scheme != "https" else {
            throw TrinsicError.error(with: .unsupportedHttpsLinking,
                message: "HTTPS callbacks require iOS 17.4 or later. Create a session with a custom-scheme redirectUrl on older iOS versions.")
        }
        return ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: completionHandler)
    }

    @available(iOS 17.4, macOS 14.4, *)
    var nativeCallback: ASWebAuthenticationSession.Callback {
        if scheme == "https" {
            return .https(host: host!, path: nativePath!)
        }
        return .customScheme(scheme)
    }
}
