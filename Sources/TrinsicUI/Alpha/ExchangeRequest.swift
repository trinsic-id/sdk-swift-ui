//
//  ExchangeRequest.swift
//  TrinsicUI
//
//  Created by Buster Townsend on 9/9/25.
//

import PassKit

public struct MdlExchangeResult {
    public let exchangeId: String
    public let token: String
}


@available(iOS 16.0, *)
public struct ExchangeRequest: Codable {
    public var exchangeId: String
    public var type: String
    public var platform: String
    public var exchangeMechanism: String
    public var requestObject: ExchangeRequestBody
    
    public func toDriversLicenseDescriptor() throws -> PKIdentityDriversLicenseDescriptor {
        return try ExchangeRequestTransformer.toPKIdentityDriversLicenseDescriptor(from: self)
    }
}

public struct ExchangeRequestBody: Codable {
    public var appleDocumentType: String
    public var requestObject: [ExchangeRequestAttribute]
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
public class ExchangeRequestTransformer {
    
    /// Transforms an ExchangeRequest into a PKIdentityDriversLicenseDescriptor
    /// - Parameter exchangeRequest: The exchange request to transform
    /// - Returns: A configured PKIdentityDriversLicenseDescriptor
    /// - Throws: ExchangeRequestTransformerError if the request cannot be transformed
    public static func toPKIdentityDriversLicenseDescriptor(from exchangeRequest: ExchangeRequest) throws -> PKIdentityDriversLicenseDescriptor {
        
        // This should only be used for mDLs
        guard exchangeRequest.type == "mdlRequest" else {
            throw ExchangeRequestTransformerError.unsupportedExchangeType(exchangeRequest.type)
        }
        
        let descriptor = PKIdentityDriversLicenseDescriptor()
        
        let body = exchangeRequest.requestObject
        for attribute in body.requestObject {
            switch attribute.attributeType {
            case "given_name":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.givenName], intentToStore: intent)
            case "family_name":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.familyName], intentToStore: intent)
            case "birth_date":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.dateOfBirth], intentToStore: intent)
            case "issue_date":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.documentIssueDate], intentToStore: intent)
            case "expiry_date":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.documentExpirationDate], intentToStore: intent)
            case "document_number":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.documentNumber], intentToStore: intent)
            case "portrait":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.portrait], intentToStore: intent)
            case "driving_privileges":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.drivingPrivileges], intentToStore: intent)
            case "issuing_authority":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                descriptor.addElements([.issuingAuthority], intentToStore: intent)
            case "age_over_18":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                if let ageOverArgument = attribute.ageOverArgument {
                    descriptor.addElements([.age(atLeast: ageOverArgument)], intentToStore: intent)
                }
            case "age_over_21":
                let intent: PKIdentityIntentToStore = attribute.intentToStore > 0 ? .mayStore(days: attribute.intentToStore) : attribute.intentToStore < 0 ? .mayStore : .willNotStore
                if let ageOverArgument = attribute.ageOverArgument {
                    descriptor.addElements([.age(atLeast: ageOverArgument)], intentToStore: intent)
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
