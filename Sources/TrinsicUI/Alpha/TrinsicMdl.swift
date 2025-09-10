//
//  TrinsicMdl.swift
//  TrinsicUI
//
//  Created by Buster Townsend on 9/9/25.
//

import PassKit

/// Class which performs mDL Exchanges. Call this after creating an exchange via Trinsic's CreateMDLExchange API
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
    @available(macOS 13.0, *)
    public func performMdlExchange(_ requestObjectBase64Url: String)
        async throws -> MdlExchangeResult
    {
        // Decode base64url string
        let exchangeRequestJson = try decodeBase64UrlString(requestObjectBase64Url)

        // Parse exchange request
        let exchangeRequest = try parseExchangeRequest(exchangeRequestJson)
        
        // Create PassKit request
        let descriptor = try exchangeRequest.toDriversLicenseDescriptor()
        let request = PKIdentityRequest()
        request.descriptor = descriptor
        request.merchantIdentifier = exchangeRequest.requestObject.merchantId

        guard
            let nonce = Data(base64Encoded: exchangeRequest.requestObject.nonce)
        else {
            throw TrinsicMdlError.invalidRequest
        }
        request.nonce = nonce

        // Perform verification
        do {
            let document = try await controller.requestDocument(request)
            let tokenBase64 = document.encryptedData.base64EncodedString()
            return MdlExchangeResult(
                exchangeId: exchangeRequest.exchangeId,
                token: tokenBase64
            )
        } catch {
            throw TrinsicMdlError.documentRequestFailed(error)
        }
    }

    /// Checks if a credential exists in the user's wallet which can fulfill a Trinsic mDL Exchange.
    /// - Parameter requestObjectBase64Url: The request object string exactly as received from Trinsic's CreateMDLExchange API
    /// - Returns: True if the user has an eligible credential; false if not
    @available(macOS 13.0, *)
    public func canRequestDriversLicense(_ requestObjectBase64Url: String)
        async throws -> Bool
    {
        // Decode base64url string
        let exchangeRequestJson = try decodeBase64UrlString(requestObjectBase64Url)

        // Parse exchange request
        let exchangeRequest = try parseExchangeRequest(exchangeRequestJson)
        
        // Create PassKit request
        let descriptor = try exchangeRequest.toDriversLicenseDescriptor()
        
        // Perform query
        return await controller.canRequestDocument(descriptor)
    }
    
    /// Checks if a credential exists in the user's wallet which can fulfill a Trinsic mDL Exchange.
    /// - Returns: True if the user has an eligible credential; false if not
    @available(macOS 13.0, *)
    public func userHasDriversLicense()
        async throws -> Bool
    {
        // Create a generic PassKit request for a drivers license
        let descriptor = PKIdentityDriversLicenseDescriptor()
        
        // Perform query
        return await controller.canRequestDocument(descriptor)
    }

    private func parseExchangeRequest(_ jsonExchangeRequest: Data) throws
        -> ParsedExchangeRequest
    {
        // Decode outer exchange request from JSON
        let decoded = try JSONDecoder().decode(
            ExchangeRequest.self,
            from: jsonExchangeRequest
        )

        // Outer exchange request contains an inner JSON string -- decode that
        let innerDecoded = try JSONDecoder().decode(
            ExchangeRequestBody.self,
            from: decoded.requestObject.data(using: .utf8)!
        )

        // Construct new bundle
        return ParsedExchangeRequest(
            exchangeId: decoded.exchangeId,
            type: decoded.type,
            platform: decoded.platform,
            exchangeMechanism: decoded.exchangeMechanism,
            requestObject: innerDecoded
        )
    }

    @available(macOS 13.0, *)
    private func decodeBase64UrlString(_ base64Url: String) throws -> Data {
        // Convert base64url to base64
        var base64 =
            base64Url
            .replacing("_", with: "/")
            .replacing("/", with: "_")

        // Add padding
        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64.append(String(repeating: "=", count: paddingLength))
        }

        // Decode base64 to a Data
        if let data = Data(base64Encoded: base64) {
            return data
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
