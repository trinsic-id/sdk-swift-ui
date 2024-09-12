import Foundation

@objc public enum TrinsicErrorCode: Int {
    case unknownError = 0
    case unparsableResultUrl = 1
    case couldNotAcquireRootViewController = 2
    case unsupportedIosVersion = 3
    case noRegisteredApplicationForLaunchUrl = 4
    case unparsableLaunchUrl = 5
    case missingSessionId = 6
    case noSupportForiOSBelow12 = 7;
    case emptyLaunchUrl = 8;
    case emptyRedirectUrl = 9
    case cannotReconstructLaunchUrl = 10
    case unparsableCallbackUrl = 11
    case unsupportedHttpsLinking = 12
}



@objc public class TrinsicError: NSObject {
    @objc public static func error(with code: TrinsicErrorCode, message: String? = nil) -> NSError {
        let domain = "id.trinsic.TrinsicError"
        let errorDescription = "\(description(for: code)): \(message ?? "")"                
        let userInfo = [NSLocalizedDescriptionKey: errorDescription]
        return NSError(domain: domain, code: code.rawValue, userInfo: userInfo)
    }
    
    @objc private static func description(for code: TrinsicErrorCode) -> String {
        switch code {
        case .unknownError:
            return "Unknown error occurred."
        case .unparsableResultUrl:
            return "The result URL could not be parsed."
        case .couldNotAcquireRootViewController:
            return "Could not acquire the root view controller."
        case .unsupportedIosVersion:
            return "Unsupported iOS version."
        case .noRegisteredApplicationForLaunchUrl:
            return "No registered application for the launch URL."
        case .unparsableLaunchUrl:
            return "The launch URL could not be parsed."
        case .missingSessionId:
            return "The session ID is missing."
        case .noSupportForiOSBelow12:
            return "This feature is not supported on iOS below version 12."
        case .emptyLaunchUrl:
            return "The launch URL is empty."
        case .emptyRedirectUrl:
            return "The redirect URL is empty."
        case .cannotReconstructLaunchUrl:
            return "Cannot reconstruct the launch URL."
        case .unparsableCallbackUrl:
            return "The callback URL could not be parsed."
        case .unsupportedHttpsLinking:
            return "HTTPS linking is not supported."
        }
    }
}
