import Foundation
import AuthenticationServices

//UIKit is only available on iOS
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@available(iOS 13.0, macOS 14.4, *)
@objc public class TrinsicUI : NSObject {
    private var presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    private var cancelHandler: (() -> Void)?
    internal var makeAuthenticationSession: (URL, SessionCallback, @escaping ASWebAuthenticationSession.CompletionHandler) throws -> ASWebAuthenticationSession = {
        try $1.makeSession(url: $0, completionHandler: $2)
    }

    @objc public override init() {
        self.presentationContextProvider = TrinsicPresentationContextProvider()
        super.init()
    }
    public init(presentationContextProvider: ASWebAuthenticationPresentationContextProviding? = nil){
        // Use a custom one if provided by library consumer, otherwise we will attempt to grab the correct presentation context.
        self.presentationContextProvider = presentationContextProvider ?? TrinsicPresentationContextProvider()
        super.init()
    }

    /// Launch a session using a custom-scheme callback.
    /// - Parameters:
    ///   - launchUrl: The URL to open. Must contain exactly one nonempty `sessionId` query parameter.
    ///     Wrappers must preserve this parameter on the URL passed to the SDK; its decoded value
    ///     must match the `sessionId` returned in the callback URL.
    ///   - callbackUrlScheme: The custom callback scheme, without a host or path.
    /// - Returns: The result with the validated session ID, or a canceled result on local cancellation.
    /// - Throws: An error if the launch or returned callback URL has a missing, empty or duplicate session ID, or the IDs differ.
    @objc public func launchSession(launchUrl: String, callbackUrlScheme: String) async throws -> LaunchSessionResult {
        return try await launchSession(launchUrl: launchUrl, callback: SessionCallback(customScheme: callbackUrlScheme))
    }

    /// Launch a session using the same complete callback URL supplied as `redirectUrl`
    /// when creating the session. HTTPS callbacks require iOS 17.4+ / macOS 14.4+
    /// and a `webcredentials` associated domain. Custom-scheme URLs are also supported.
    /// Apple matches HTTPS callbacks by host and decoded path, and custom callbacks by scheme.
    /// - Parameters:
    ///   - launchUrl: The URL to open. Must contain exactly one nonempty `sessionId` query parameter.
    ///     Wrappers must preserve this parameter on the URL passed to the SDK; its decoded value
    ///     must match the `sessionId` returned in the callback URL.
    ///   - callbackUrl: The callback URL supplied as `redirectUrl` when creating the session.
    /// - Returns: The result with the validated session ID, or a canceled result on local cancellation.
    /// - Throws: An error if the launch or returned callback URL has a missing, empty or duplicate session ID, or the IDs differ.
    @objc public func launchSession(launchUrl: String, callbackUrl: String) async throws -> LaunchSessionResult {
        return try await launchSession(launchUrl: launchUrl, callback: SessionCallback(url: callbackUrl))
    }

    private func launchSession(launchUrl: String, callback: SessionCallback) async throws -> LaunchSessionResult {
        return try await withCheckedThrowingContinuation( { continuation in
            Task { @MainActor in
                // One-shot guard so cancel() and the native completion handler can race without double-resuming the continuation.
                let resumer = ResumeOnce()
                var completionHandler: ((URL?, Error?) -> Void)?
                var sessionToKeepAlive: Any? // if we do not keep the session alive, it will get closed immediately while showing the dialog
                do {
                    let (parsedLaunchUrl, expectedSessionId) = try self.parseLaunchUrl(launchUrl: launchUrl)

                    completionHandler = { [weak self] (url: URL?, err: Error?) in
                        completionHandler = nil

                        // If cancel() already resumed the continuation, skip — the UI is already torn down too.
                        guard resumer.tryConsume() else { return }
                        self?.cancelHandler = nil

                        // Release the retained session even when the native UI reports cancellation.
                        let completedSession = sessionToKeepAlive as? ASWebAuthenticationSession
                        sessionToKeepAlive = nil
                        if err == nil || (err as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                            completedSession?.cancel()
                        }

                        if let err = err {
                            if case ASWebAuthenticationSessionError.canceledLogin = err {
                                continuation.resume(returning: LaunchSessionResult(canceled: true, sessionId: nil, redirectToken: nil, callbackUrl: nil))
                                return;
                            }
                            else {

                                continuation.resume(throwing:  TrinsicError.error(with: .unknownError, message: err.localizedDescription))
                                return
                            }
                        }
                        guard let url = url else {
                            continuation.resume(throwing: TrinsicError.error(with: .unknownError, message: "We did not receive a url from the native completion handler"))
                            return
                        }
                        do {
                            continuation.resume(returning: try Self.parseUrl(url: url, expectedSessionId: expectedSessionId))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }

                    let session = try self.makeAuthenticationSession(parsedLaunchUrl, callback, completionHandler!)
                    sessionToKeepAlive = session

                    // cancel() dismisses the system UI AND resumes the continuation directly — the native completion handler is not reliably invoked on programmatic .cancel().
                    self.cancelHandler = { [weak self] in
                        guard resumer.tryConsume() else { return }
                        self?.cancelHandler = nil
                        session.cancel()
                        sessionToKeepAlive = nil
                        completionHandler = nil
                        continuation.resume(returning: LaunchSessionResult(canceled: true, sessionId: nil, redirectToken: nil, callbackUrl: nil))
                    }

                    session.presentationContextProvider = self.presentationContextProvider;
                    if !session.start() {
                        completionHandler?(nil, TrinsicError.error(with: .unknownError, message: "Could not start the web authentication session."))
                    }
                }
                catch {
                    completionHandler = nil
                    guard resumer.tryConsume() else { return }
                    continuation.resume(throwing: error)
                }
            }
        })
    }

    /// Cancels the active ``ASWebAuthenticationSession`` started by either `launchSession` overload, if one is in flight.
    /// The corresponding ``launchSession`` call will return a ``LaunchSessionResult`` with ``canceled`` set to `true`.
    /// Has no effect if no session is currently active.
    @objc public func cancel() {
        cancelHandler?()
    }

    private static func parseUrl(url: URL, expectedSessionId: String) throws -> LaunchSessionResult {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let sessionIds = queryItems.filter { $0.name == "sessionId" }
        guard sessionIds.count == 1,
              let sessionId = sessionIds[0].value,
              sessionId == expectedSessionId else {
            throw TrinsicError.error(with: .unparsableResultUrl,
                message: "The result URL must contain exactly one sessionId matching the launch URL.")
        }

        func value(for name: String) -> String? {
            guard let value = queryItems.first(where: { $0.name == name })?.value,
                  !value.isEmpty else { return nil }
            return value
        }

        return LaunchSessionResult(
            canceled: Bool(value(for: "canceled") ?? "") ?? false,
            sessionId: sessionId,
            redirectToken: value(for: "redirectToken"),
            callbackUrl: url.absoluteString
        )
    }
    
    private func parseLaunchUrl(launchUrl: String) throws -> (url: URL, sessionId: String) {
        guard !launchUrl.isEmpty else {
            throw TrinsicError.error(with: .emptyLaunchUrl, message: "launchURL is empty")
        }
        
        guard let url = URL(string: launchUrl) else {
            throw TrinsicError.error(with: .unparsableLaunchUrl, message: "Cannot make URL from launchUrl")
        }

        let sessionIds = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name == "sessionId" } ?? []
        guard sessionIds.count == 1,
              let sessionId = sessionIds[0].value,
              !sessionId.isEmpty else {
            throw TrinsicError.error(with: .missingSessionId,
                message: "launchUrl must contain exactly one nonempty sessionId query parameter.")
        }

        return (url, sessionId)
    }
}

private final class ResumeOnce {
    private let lock = NSLock()
    private var consumed = false

    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if consumed { return false }
        consumed = true
        return true
    }
}
