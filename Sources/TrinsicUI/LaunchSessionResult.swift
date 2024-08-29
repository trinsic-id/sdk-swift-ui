import Foundation

@objc public class LaunchSessionResult : NSObject {
    @objc public let sessionId: String?
    @objc public let resultsAccessKey: String?
    @objc public let success: Bool
    @objc public let canceled: Bool
    
    @objc init(success: Bool, canceled: Bool, sessionId: String?, resultsAccessKey: String?) {
            self.success = success
            self.canceled = canceled
            self.sessionId = sessionId
            self.resultsAccessKey = resultsAccessKey
        }
}
