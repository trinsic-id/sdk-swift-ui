import Foundation

@objc public class LaunchSessionResult : NSObject {
    private let legacyResultsAccessKey: String?
    private let legacySuccess: Bool

    @objc public let sessionId: String?

    /// The `redirectToken` from the callback redirect, if present.
    ///
    /// NOTE: As of September 1 2026, this field always has a value of `nil`, as the relevant platform changes
    /// have not yet been released. However, in the very near future, this field will be populated
    /// for all successful Sessions.
    ///
    /// If this value is non-`nil`, send it to your backend; it will play a core role in future
    /// high-assurance / same-device guarantees.
    ///
    /// For now, your backend should not do anything with this value if it is sent. When
    /// this feature is fully released, Trinsic will provide guidance
    ///
    /// This field is present before the feature is fully released to ensure that the necessary
    /// changes upon release are backend-only, and do not require app or SDK updates.
    @objc public let redirectToken: String?

    @available(*, deprecated, message: "Use the resultsAccessKey stored by your backend when the Session was created instead.")
    @objc public var resultsAccessKey: String? { legacyResultsAccessKey }

    @available(*, deprecated, message: "Use the Trinsic API as the authoritative source for Session success instead.")
    @objc public var success: Bool { legacySuccess }

    /// Whether the Session was locally canceled by the user (e.g. by hitting the "Cancel" button on the
    /// `ASWebAuthenticationSession` interface).
    ///
    /// NOTE that if the user canceled the Session by, e.g., clicking a "Cancel" button in a web UI - such that the Trinsic Session itself
    /// entered the canceled state - this will have a value of `false`.
    ///
    /// This only has a value of `true` if the user canceled the Session using an OS feature which immediately
    /// ended the `ASWebAuthenticationSession`. In this case, Trinsic's backend never receives notification that
    /// the Session has been canceled; therefore, the Session will not transition to the canceled state on the Trinsic platform.
    @objc public let canceled: Bool
    
    @objc init(success: Bool, canceled: Bool, sessionId: String?, redirectToken: String?, resultsAccessKey: String?) {
        self.legacySuccess = success
        self.canceled = canceled
        self.sessionId = sessionId
        self.redirectToken = redirectToken
        self.legacyResultsAccessKey = resultsAccessKey
    }
}
