//
//  TrinsicMdl.swift
//  TrinsicUI
//
//  Created by Buster Townsend on 9/9/25.
//

import PassKit

/**
 Class which performs mDL Exchanges. Call this after creating an exchange via Trinsic's CreateMDLExchange API
 */
@available(iOS 17.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
@MainActor
public class TrinsicMdl {
    private let controller: PKIdentityAuthorizationController

    public init(controller: PKIdentityAuthorizationController? = nil) {
        self.controller = controller ?? PKIdentityAuthorizationController()
    }
    
    
    /// Perform an mDL Exchange
    /// - Parameter requestObjectBase64Url: The request object string exactly as received from Trinsic's CreateMDLExchange API
    /// - Returns: An exchange result containing an exchangeId and token
    public func performMdlExchange(requestObjectBase64Url: String) async throws -> MdlExchangeResult {
        let exchangeRequest = try decodeBase64UrlString(requestObjectBase64Url)
        let descriptor = try exchangeRequest.toDriversLicenseDescriptor()
        let request = PKIdentityRequest()
        request.descriptor = descriptor
        request.merchantIdentifier = exchangeRequest.requestObject.merchantId

        guard let nonce = Data(base64Encoded: exchangeRequest.requestObject.nonce) else {
            throw TrinsicMdlError.invalidRequest
        }
        request.nonce = nonce

        do {
            let document = try await controller.requestDocument(request)
            let tokenBase64 = document.encryptedData.base64EncodedString()
            return MdlExchangeResult(exchangeId: exchangeRequest.exchangeId, token: tokenBase64)
        } catch {
            throw TrinsicMdlError.documentRequestFailed(error)
        }
    }
    
    
    /// Checks if a credential exists in the user's wallet which can fulfill a Trinsic mDL Exchange.
    /// - Parameter requestObjectBase64Url: The request object string exactly as received from Trinsic's CreateMDLExchange API
    /// - Returns: True if the user has an eligible credential; false if not
    public func canRequestDriversLicense(_ requestObjectBase64Url: String) async throws -> Bool {
        let exchangeRequest = try decodeBase64UrlString(requestObjectBase64Url)
        let descriptor = try exchangeRequest.toDriversLicenseDescriptor()
        return await withCheckedContinuation { continuation in
            controller.checkCanRequestDocument(descriptor) { canRequest in
                continuation.resume(returning: canRequest)
            }
        }
    }
    
    private func decodeBase64UrlString(_ requestBase64Url: String) throws -> ExchangeRequest {
        var requestBase64 = requestBase64Url
            .replacing("_", with: "/")
            .replacing("/", with: "_")
        
        let paddingLength = 4 - (requestBase64.count % 4)
        if paddingLength < 4 {
            requestBase64.append(String(repeating: "=", count: paddingLength))
        }
        
        if let data = Data(base64Encoded: requestBase64) {
            do {
                let decoded = try JSONDecoder().decode(ExchangeRequest.self, from: data)
                return decoded
            } catch {
                throw TrinsicMdlError.unsupportedType
            }
        }
        throw TrinsicMdlError.invalidRequest
    }
}

public enum TrinsicMdlError: Error {
    case notSupported
    case deviceDoesNotSupportMdl
    case unsupportedType
    case invalidRequest
    case documentRequestFailed(Error)
    case unknownError(Error)
}
