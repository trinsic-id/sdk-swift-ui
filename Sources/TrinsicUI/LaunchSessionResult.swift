import Foundation

@objc public class LaunchSessionResult : NSObject {
    /// The `sessionId` from the callback redirect, validated against the launch URL.
    /// `nil` when the session is locally canceled without a callback URL.
    /// If you rely on this value beyond Trinsic's obsoletion period, prefer parsing the full `callbackUrl` on your backend.
    @objc public let sessionId: String?

    /// The `redirectToken` from the callback redirect, or `nil` if missing or empty.
    /// If you rely on this value beyond Trinsic's obsoletion period, prefer parsing the full `callbackUrl` on your backend.
    @objc public let redirectToken: String?

    /// The `redirectReason` from the callback redirect, or `nil` if missing or empty.
    /// If you rely on this value beyond Trinsic's obsoletion period, prefer parsing the full `callbackUrl` on your backend.
    @objc public let redirectReason: String?

    /// The full URL returned by the native authentication session, including query and fragment.
    /// `nil` when the session is locally canceled without a callback URL.
    @objc public let callbackUrl: String?

    /// Whether the native session was canceled or the callback contains `canceled=true`.
    /// If you rely on the callback's cancellation flag beyond Trinsic's obsoletion period, prefer parsing the full `callbackUrl` on your backend.
    @objc public let canceled: Bool

    @objc init(canceled: Bool, sessionId: String?, redirectToken: String?, redirectReason: String? = nil, callbackUrl: String?) {
        self.canceled = canceled
        self.sessionId = sessionId
        self.redirectToken = redirectToken
        self.redirectReason = redirectReason
        self.callbackUrl = callbackUrl
    }
}
