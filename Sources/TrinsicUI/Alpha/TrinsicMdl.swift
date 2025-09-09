//
//  TrinsicMdl.swift
//  TrinsicUI
//
//  Created by Buster Townsend on 9/9/25.
//

import PassKit

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
@MainActor
public class TrinsicMdl {
    
    private let controller: PKIdentityAuthorizationController

    public init(controller: PKIdentityAuthorizationController? = nil) {
        self.controller = controller ?? PKIdentityAuthorizationController()
    }
    
    public func performMdlExchange(requestObjectBase64: String) async throws -> MdlExchangeResult {
        let exchangeRequest = try decodeBase64String(requestObjectBase64)
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
    
    
    public func canRequestDriversLicense(_ requestObjectBase64: String) async throws -> Bool {
        let exchangeRequest = try decodeBase64String(requestObjectBase64)
        let descriptor = try exchangeRequest.toDriversLicenseDescriptor()
        return await withCheckedContinuation { continuation in
            controller.checkCanRequestDocument(descriptor) { canRequest in
                continuation.resume(returning: canRequest)
            }
        }
    }
    
    private func decodeBase64String(_ requestBase64: String) throws -> ExchangeRequest {
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
