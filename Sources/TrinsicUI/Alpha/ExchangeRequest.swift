//
//  ExchangeRequest.swift
//  TrinsicUI
//
//  Created by Buster Townsend on 9/9/25.
//

import PassKit


/// The result of an mDL Exchange
public struct MdlExchangeResult {
    /// The ID of the Trinsic mDL Exchange which this result is for
    public let exchangeId: String
    
    /// The token string which should be sent to Trinsic's FinalizeMDLExchange API exactly as-is
    public let token: String
}


@available(iOS 16.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
public struct ExchangeRequest: Codable {
    public var exchangeId: String
    public var type: String
    public var platform: String
    public var exchangeMechanism: String
    public var requestObject: ExchangeRequestBody
    
    public func toDriversLicenseDescriptor() throws -> PKIdentityDriversLicenseDescriptor {
        return try ExchangeRequestTransformer
            .toPKIdentityDriversLicenseDescriptor(from: self)
    }
}

public struct ExchangeRequestBody: Codable {
    public var appleDocumentType: String
    public var requestAttributes: [ExchangeRequestAttribute]
    public var nonce: String
    public var merchantId: String
    public var teamId: String
}

public struct ExchangeRequestAttribute: Codable {
    public var attributeType: String
    public var intentToStore: Int
    public var ageOverArgument: Int?
}

// MARK: - Exchange Request Transformer

public enum ExchangeRequestTransformerError: Error {
    case unsupportedExchangeType(String)
    case missingExchangeBody
    case invalidRequestData
    
    public var localizedDescription: String {
        switch self {
        case .unsupportedExchangeType(let type):
            return "Unsupported exchange type: \(type)"
        case .missingExchangeBody:
            return "Exchange request body is required"
        case .invalidRequestData:
            return "Invalid request data"
        }
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
public class ExchangeRequestTransformer {
    
    /// Transforms an ExchangeRequest into a PKIdentityDriversLicenseDescriptor
    /// - Parameter exchangeRequest: The exchange request to transform
    /// - Returns: A configured PKIdentityDriversLicenseDescriptor
    /// - Throws: ExchangeRequestTransformerError if the request cannot be transformed
    public static func toPKIdentityDriversLicenseDescriptor(from exchangeRequest: ExchangeRequest) throws -> PKIdentityDriversLicenseDescriptor {
        
        // This should only be used for mDLs
        guard exchangeRequest.type == "mdlRequest" else {
            throw ExchangeRequestTransformerError
                .unsupportedExchangeType(exchangeRequest.type)
        }
        
        let descriptor = PKIdentityDriversLicenseDescriptor()
        
        let requestAttributes = exchangeRequest.requestObject.requestAttributes
        for attribute in requestAttributes {
            switch attribute.attributeType {
            case "GivenName":
               
                descriptor
                    .addElements(
                        [.givenName],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "FamilyName":
               
                descriptor
                    .addElements(
                        [.familyName],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "DateOfBirth":
               
                descriptor
                    .addElements(
                        [.dateOfBirth],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "Address":
               
                descriptor
                    .addElements(
                        [.address],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "IssuingAuthority":
               
                descriptor
                    .addElements(
                        [.issuingAuthority],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "DocumentIssueDate":
               
                descriptor
                    .addElements(
                        [.documentIssueDate],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "DocumentExpirationDate":
               
                descriptor
                    .addElements(
                        [.documentExpirationDate],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "DocumentNumber":
               
                descriptor
                    .addElements(
                        [.documentNumber],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "Portrait":
               
                descriptor
                    .addElements(
                        [.portrait],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "DrivingPrivileges":
               
                descriptor
                    .addElements(
                        [.drivingPrivileges],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "Age":
               
                descriptor
                    .addElements(
                        [.age],
                        intentToStore:
                                .intent(attribute.intentToStore)
                    )
            case "AgeAtLeastX":
               
                if let ageOverArgument = attribute.ageOverArgument {
                    descriptor
                        .addElements(
                            [.age(atLeast: ageOverArgument)],
                            intentToStore:
                                    .intent(attribute.intentToStore)
                        )
                }
            default:
                // For unknown attribute types, we'll continue without adding them
                // we will need to figure out how to handle this better in the future
                break
            }
        }
        
        return descriptor
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
public extension PKIdentityIntentToStore {
    static func intent(_ intentToStore: Int) -> PKIdentityIntentToStore {
        return intentToStore > 0 ? 
            .mayStore(
                days: intentToStore
            ) : intentToStore < 0 ? .mayStore : .willNotStore
    }
}
