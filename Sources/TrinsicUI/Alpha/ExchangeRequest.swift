import Foundation

/// The result of a native Wallet exchange. Submit `token` to Trinsic unchanged.
public struct MdlExchangeResult {
    public let exchangeId: String
    public let token: String

    internal init(exchangeId: String, encryptedData: Data) {
        self.exchangeId = exchangeId
        self.token = encryptedData.base64EncodedString()
    }
}

public struct ExchangeRequest: Codable {
    public var exchangeId: String
    public var type: String
    public var platform: String
    public var exchangeMechanism: String
    public var requestObject: String
}

public struct ParsedExchangeRequest {
    public var exchangeId: String
    public var type: String
    public var platform: String
    public var exchangeMechanism: String
    public var requestObject: ExchangeRequestBody
}

/// Shared transaction binding plus either a legacy single document or document alternatives.
public struct ExchangeRequestBody: Codable {
    /// Legacy single-document fields. Empty when `documentRequests` is used.
    public var appleDocumentType: String
    public var requestedAttributes: [ExchangeRequestAttribute]
    public var region: String?
    /// Alternatives: any ONE supported document may satisfy the request.
    public var documentRequests: [ExchangeDocumentRequest]?
    public var nonce: String
    public var merchantId: String
    public var teamId: String

    public init(appleDocumentType: String, requestedAttributes: [ExchangeRequestAttribute],
                nonce: String, merchantId: String, teamId: String, region: String? = nil) {
        self.appleDocumentType = appleDocumentType
        self.requestedAttributes = requestedAttributes
        self.region = region
        self.nonce = nonce
        self.merchantId = merchantId
        self.teamId = teamId
    }

    public init(documentRequests: [ExchangeDocumentRequest], nonce: String, merchantId: String, teamId: String) {
        self.appleDocumentType = ""
        self.requestedAttributes = []
        self.documentRequests = documentRequests
        self.nonce = nonce
        self.merchantId = merchantId
        self.teamId = teamId
    }

    private enum CodingKeys: String, CodingKey {
        case appleDocumentType, requestedAttributes, region, documentRequests, nonce, merchantId, teamId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nonce = try container.decode(String.self, forKey: .nonce)
        merchantId = try container.decode(String.self, forKey: .merchantId)
        teamId = try container.decode(String.self, forKey: .teamId)
        if container.contains(.documentRequests) {
            guard !container.contains(.appleDocumentType), !container.contains(.requestedAttributes),
                  !container.contains(.region) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Use documentRequests or the legacy single-document fields, not both."))
            }
            documentRequests = try container.decode([ExchangeDocumentRequest].self, forKey: .documentRequests)
            appleDocumentType = ""
            requestedAttributes = []
        } else {
            let document = try ExchangeDocumentRequest(from: decoder)
            appleDocumentType = document.appleDocumentType
            requestedAttributes = document.requestedAttributes
            region = document.region
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(merchantId, forKey: .merchantId)
        try container.encode(teamId, forKey: .teamId)
        if let documentRequests {
            try container.encode(documentRequests, forKey: .documentRequests)
        } else {
            try container.encode(appleDocumentType, forKey: .appleDocumentType)
            try container.encode(requestedAttributes, forKey: .requestedAttributes)
            try container.encodeIfPresent(region, forKey: .region)
        }
    }

    internal var documents: [ExchangeDocumentRequest] {
        documentRequests ?? [.init(appleDocumentType: appleDocumentType,
                                  requestedAttributes: requestedAttributes, region: region)]
    }
}

public struct ExchangeDocumentRequest: Codable {
    public var appleDocumentType: String
    public var requestedAttributes: [ExchangeRequestAttribute]
    /// ISO 3166-1 alpha-2 region for NationalIDCard; use JP for Japan-specific fields.
    public var region: String?

    public init(appleDocumentType: String, requestedAttributes: [ExchangeRequestAttribute], region: String? = nil) {
        self.appleDocumentType = appleDocumentType
        self.requestedAttributes = requestedAttributes
        self.region = region
    }

    private enum CodingKeys: String, CodingKey { case appleDocumentType, requestedAttributes, region }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appleDocumentType = try container.decode(String.self, forKey: .appleDocumentType)
        // Future types may have a different schema. Read only their discriminator
        // so they cannot prevent a known alternative from being used.
        guard NativeWalletDocumentType(rawValue: appleDocumentType) != nil else {
            requestedAttributes = []
            return
        }
        requestedAttributes = try container.decode([ExchangeRequestAttribute].self, forKey: .requestedAttributes)
        region = try container.decodeIfPresent(String.self, forKey: .region)
    }
}

internal enum NativeWalletDocumentType: String {
    case driversLicense = "DriversLicense"
    case photoID = "PhotoID"
    case nationalIDCard = "NationalIDCard"
}

internal enum NativeWalletAttributeType: String {
    case givenName = "GivenName", familyName = "FamilyName", portrait = "Portrait"
    case address = "Address", dateOfBirth = "DateOfBirth", age = "Age", ageAtLeastX = "AgeAtLeastX"
    case sex = "Sex", documentNumber = "DocumentNumber", issuingAuthority = "IssuingAuthority"
    case documentIssueDate = "DocumentIssueDate", documentExpirationDate = "DocumentExpirationDate"
    case drivingPrivileges = "DrivingPrivileges", documentDHSComplianceStatus = "DocumentDHSComplianceStatus"
    case height = "Height", weight = "Weight", eyeColor = "EyeColor", hairColor = "HairColor"
    case organDonorStatus = "OrganDonorStatus", veteranStatus = "VeteranStatus"

    func supports(_ documentType: NativeWalletDocumentType) -> Bool {
        switch self {
        case .issuingAuthority, .documentIssueDate, .documentExpirationDate:
            return documentType != .nationalIDCard
        case .drivingPrivileges, .documentDHSComplianceStatus, .height, .weight, .eyeColor,
             .hairColor, .organDonorStatus, .veteranStatus:
            return documentType == .driversLicense
        default:
            return true
        }
    }
}

public struct ExchangeRequestAttribute: Codable {
    public var attributeType: String
    public var intentToStore: Int
    /// Legacy Swift name, retained for source and decoding compatibility.
    public var ageOverArgument: Int?
    public var ageAtLeastXArgument: Int? {
        get { ageOverArgument }
        set { ageOverArgument = newValue }
    }

    public init(attributeType: String, intentToStore: Int, ageAtLeastXArgument: Int? = nil) {
        self.attributeType = attributeType
        self.intentToStore = intentToStore
        self.ageOverArgument = ageAtLeastXArgument
    }

    private enum CodingKeys: String, CodingKey {
        case attributeType, intentToStore, ageAtLeastXArgument, ageOverArgument
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attributeType = try container.decode(String.self, forKey: .attributeType)
        intentToStore = try container.decode(Int.self, forKey: .intentToStore)
        // Storage intent is shared by every attribute. Only interpret type-specific
        // arguments for known attributes; the transformer rejects the entire
        // document alternative when it encounters an unknown attribute.
        guard NativeWalletAttributeType(rawValue: attributeType) != nil else { return }
        let current = try container.decodeIfPresent(Int.self, forKey: .ageAtLeastXArgument)
        let legacy = try container.decodeIfPresent(Int.self, forKey: .ageOverArgument)
        if let current, let legacy, current != legacy {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Conflicting age threshold arguments."))
        }
        ageOverArgument = current ?? legacy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attributeType, forKey: .attributeType)
        try container.encode(intentToStore, forKey: .intentToStore)
        try container.encodeIfPresent(ageAtLeastXArgument, forKey: .ageAtLeastXArgument)
    }
}

public enum ExchangeRequestTransformerError: Error, LocalizedError {
    case unsupportedChallengeVersion
    case unsupportedExchangeType(String)
    case unsupportedPlatform(String)
    case unsupportedDocumentType(String)
    case noSupportedDocuments
    case unsupportedAttribute(String)
    case invalidAttribute(String)
    case emptyRequestedAttributes(String)
    case missingExchangeBody
    case invalidRequestData

    public var errorDescription: String? { localizedDescription }

    public var localizedDescription: String {
        switch self {
        case .unsupportedChallengeVersion: return "No native Wallet challenge version is supported by this SDK."
        case .unsupportedExchangeType(let type): return "Unsupported exchange type: \(type)"
        case .unsupportedPlatform(let platform): return "Unsupported Wallet platform: \(platform)"
        case .unsupportedDocumentType(let type): return "Unsupported document type for this operation: \(type)"
        case .noSupportedDocuments: return "No complete requested document is supported by this SDK and iOS version."
        case .unsupportedAttribute(let attribute): return "Unsupported identity attribute: \(attribute)"
        case .invalidAttribute(let attribute): return "Invalid identity attribute or argument: \(attribute)"
        case .emptyRequestedAttributes(let type): return "No identity attributes were requested for \(type)."
        case .missingExchangeBody: return "Exchange request body is required."
        case .invalidRequestData: return "Invalid native Wallet request data."
        }
    }
}
