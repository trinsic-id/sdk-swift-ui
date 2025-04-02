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
    
    @objc public override init() {
        self.presentationContextProvider = TrinsicPresentationContextProvider()
        super.init()
    }
    public init(presentationContextProvider: ASWebAuthenticationPresentationContextProviding? = nil){
        // Use a custom one if provided by library consumer, otherwise we will attempt to grab the correct presentation context.
        self.presentationContextProvider = presentationContextProvider ?? TrinsicPresentationContextProvider()
        super.init()
    }
    
    
    @objc public func launchSession(launchUrl: String, callbackUrlScheme: String) async throws -> LaunchSessionResult {
        return try await withCheckedThrowingContinuation( { continuation in
            Task {
                var completionHandler: ((URL?, Error?) -> Void)?
                var sessionToKeepAlive: Any? // if we do not keep the session alive, it will get closed immediately while showing the dialog
                do {
                    let formattedLaunchUrl = try self.validateAndFormatLaunchUrl(launchUrl: launchUrl)
                    
                    completionHandler = { (url: URL?, err: Error?) in
                        completionHandler = nil
                        
                        //Clean up resources, but if canceled we should not as it's already deprovisioned
                        if err == nil || (err as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                            if (sessionToKeepAlive != nil) {
                                (sessionToKeepAlive as! ASWebAuthenticationSession).cancel()
                                sessionToKeepAlive = nil
                            }
                        }
                        
                        if let err = err {
                            if case ASWebAuthenticationSessionError.canceledLogin = err {
                                continuation.resume(returning: LaunchSessionResult.init(success: false, canceled: true, sessionId: nil, resultsAccessKey: nil))
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
                        let (result, parseError) = self.parseUrl(url: url)
                        if let parseError = parseError {
                            continuation.resume(throwing: parseError)
                        }
                        else if let result = result {
                            continuation.resume(returning: result)
                        }
                        else {
                            continuation.resume(throwing: TrinsicError.error(with: .unknownError, message: "An unknown error occured, we should never hit this code-branch"))
                        }
                    }
                    
                    var _session: ASWebAuthenticationSession? = nil
                    if #available(iOS 17.4, *) {
                        if (callbackUrlScheme == "https") {
                            //When appropriate we should investigate/dive deeper.
                            throw TrinsicError.error(with: .unsupportedHttpsLinking, message: "We don't support https deep linking yet. Please contact Trinsic support.")
                        } else {
                            _session = ASWebAuthenticationSession(url: formattedLaunchUrl, callback: ASWebAuthenticationSession.Callback.customScheme(callbackUrlScheme), completionHandler: completionHandler!)
                        }
                    } else {
                        _session = ASWebAuthenticationSession(url: formattedLaunchUrl, callbackURLScheme: callbackUrlScheme, completionHandler: completionHandler!)
                    }
                    let session = _session!
                    sessionToKeepAlive = session
                    session.presentationContextProvider = self.presentationContextProvider;
                    session.start()
                }
                catch {
                    continuation.resume(throwing: error)
                }
            }
        })
    }
    
    private func parseUrl(url: URL) -> (result: LaunchSessionResult?, parseError: Error?) {
        // Parse launchUrl into a URLComponents object
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            return (result: nil, parseError: TrinsicError.error(with: .unparsableResultUrl, message: "Cannot make URLComponents from result url"))
        }
        
        let queryItems = urlComponents.queryItems ?? []

        guard let successString = queryItems.first(where: { $0.name == "success" })?.value,
            !successString.isEmpty,
            let success = Bool(successString) else {
            return (result: nil, parseError: TrinsicError.error(with: .unparsableResultUrl, message: "Cannot find success in result url"))
        }
        
        let canceledString = queryItems.first(where: { $0.name == "canceled" })?.value
        let canceled = (canceledString != nil && !canceledString!.isEmpty && Bool(canceledString!) == true)
        
        guard let sessionId = queryItems.first(where: { $0.name == "sessionId" })?.value,
            !sessionId.isEmpty else {
            return (result: nil, parseError: TrinsicError.error(with: .unparsableResultUrl, message: "Cannot find sessionId in result url"))
        }
        
        guard let resultsAccessKey = queryItems.first(where: { $0.name == "resultsAccessKey" })?.value,
            !resultsAccessKey.isEmpty else {
            return (result: nil, parseError: TrinsicError.error(with: .unparsableResultUrl, message: "cannot find resultsAccessKey in result url"))
        }
        let result = LaunchSessionResult.init(success: success, canceled: canceled, sessionId: sessionId, resultsAccessKey: resultsAccessKey)
        return (result: result, parseError: nil)
    }
    
    private func validateAndFormatLaunchUrl(launchUrl: String) throws -> URL {
        guard !launchUrl.isEmpty else {
            throw TrinsicError.error(with: .emptyLaunchUrl, message: "launchURL is empty")
        }
        
        // Parse launchUrl into a URL object
        guard URL(string: launchUrl) != nil else {
            throw TrinsicError.error(with: .unparsableLaunchUrl, message: "Cannot make URL from launchUrl")
        }
          
        // Parse launchUrl into a URLComponents object
        guard var urlComponents = URLComponents(string: launchUrl) else {
            throw TrinsicError.error(with: .unparsableLaunchUrl, message: "Cannot make URLComponents from launchUrl")
        }
          
        var queryItems = urlComponents.queryItems ?? []

        guard let sessionId = queryItems.first(where: { $0.name == "sessionId" })?.value,
            !sessionId.isEmpty else {
            throw TrinsicError.error(with: .missingSessionId, message: "Can't find session id on launchUrl")
        }

        // Launchmode affects some validation checks on our backend to ensure a session for a platform has all the required parameters
        if queryItems.first(where: { $0.name == "launchMode" }) == nil {
          queryItems.append(URLQueryItem(name: "launchMode", value: "mobile"))
        }
    

        // Update the URL components with the new query items
        urlComponents.queryItems = queryItems

        // Reconstruct the updated URL which includes the launch mode and redirect url.
        guard let updatedUrl = urlComponents.url else {
            throw TrinsicError.error(with: .cannotReconstructLaunchUrl, message: "Cannot get url from reconstructed launchUrl")
        }
        
        return updatedUrl
    }
}
