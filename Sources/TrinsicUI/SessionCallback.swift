import AuthenticationServices
import Foundation

/// Configures Apple's native callback matching: HTTPS host and decoded path,
/// or just the scheme for custom-scheme callbacks.
internal struct SessionCallback {
    let scheme: String
    let host: String?
    let path: String?

    init(customScheme: String) throws {
        guard !customScheme.isEmpty else {
            throw TrinsicError.error(with: .emptyCallbacklUrl)
        }
        // Malformed schemes can raise an Objective-C exception in the native session initializer.
        guard customScheme.range(of: "\\A[A-Za-z][A-Za-z0-9+.-]*\\z", options: .regularExpression) != nil,
              !["http", "https"].contains(customScheme.lowercased()) else {
            throw TrinsicError.error(with: .unparsableCallbackUrl,
                message: "Supply only a valid custom scheme, or use callbackUrl with a complete callback URL.")
        }
        scheme = customScheme.lowercased()
        host = nil
        path = nil
    }

    init(url: String) throws {
        guard !url.isEmpty else {
            throw TrinsicError.error(with: .emptyCallbacklUrl)
        }
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              scheme != "http" else {
            throw TrinsicError.error(with: .unparsableCallbackUrl,
                message: "Use an absolute HTTPS or custom-scheme callback URL.")
        }
        self.scheme = scheme
        if scheme == "https" {
            // URL.host preserves the ASCII (IDNA) form required by Apple's matcher.
            guard let host = components.url?.host, !host.isEmpty else {
                throw TrinsicError.error(with: .unparsableCallbackUrl,
                    message: "An HTTPS callback URL must have a host.")
            }
            self.host = host.lowercased()
            path = components.path.isEmpty ? "/" : components.path
        } else {
            host = nil
            path = nil
        }
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
            return .https(host: host!, path: path!)
        }
        return .customScheme(scheme)
    }
}
