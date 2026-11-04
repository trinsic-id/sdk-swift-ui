import Foundation

@objc public class LaunchSessionResult : NSObject {
    /// The `sessionId` from the callback redirect, validated against the launch URL.
    /// `nil` when the session is locally canceled without a callback URL.
    @objc public let sessionId: String?

    /// The `redirectToken` from the callback redirect, or `nil` if missing or empty.
    @objc public let redirectToken: String?

    /// The full URL returned by the native authentication session, including query and fragment.
    /// `nil` when the session is locally canceled without a callback URL.
    @objc public let callbackUrl: String?

    /// Whether the native session was canceled or the callback contains `canceled=true`.
    @objc public let canceled: Bool

    @objc init(canceled: Bool, sessionId: String?, redirectToken: String?, callbackUrl: String?) {
        self.canceled = canceled
        self.sessionId = sessionId
        self.redirectToken = redirectToken
        self.callbackUrl = callbackUrl
    }
}
