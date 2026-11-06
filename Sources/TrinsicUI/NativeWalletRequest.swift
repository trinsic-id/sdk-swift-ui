import Foundation
import OSLog

/// Structural diagnostics only: never contains a nonce, credential, or response token.
public struct NativeWalletDiagnostic: Equatable, Sendable {
    public enum Code: String, Sendable {
        case unsupportedDocumentType, documentUnavailableOnOS, unsupportedAttribute, selectingSingleDocument, noSupportedDocuments
        case requestParsed, availabilityChecked, documentSelected
    }
    public enum Level: String, Sendable { case info, warning, error }
    public let code: Code
    public let level: Level
    public let documentType: String?
    public let attributeType: String?
    /// PassKit's result for availabilityChecked. It does not identify why a check failed.
    public let isAvailable: Bool?
    /// Parsed request configuration, present only for requestParsed.
    public let request: NativeWalletRequestSummary?
}

/// Explicitly allowlisted request metadata; excludes nonce values, raw JSON,
/// unknown properties, credentials and response data. IDs are for correlation.
public struct NativeWalletRequestSummary: Equatable, Sendable {
    public struct Attribute: Equatable, Sendable {
        public let attributeType: String
        public let intentToStore: Int
        public let ageAtLeastXArgument: Int?
    }

    public struct Document: Equatable, Sendable {
        public let documentType: String
        public let region: String?
        public let attributes: [Attribute]
    }

    public let version: String
    public let exchangeId: String
    public let merchantId: String
    public let teamId: String
    public let nonceByteCount: Int
    public let documents: [Document]

    internal init(exchange: ParsedExchangeRequest) throws {
        version = "v1"
        exchangeId = exchange.exchangeId
        merchantId = exchange.requestObject.merchantId
        teamId = exchange.requestObject.teamId
        nonceByteCount = try NativeWalletBase64.decode(exchange.requestObject.nonce).count
        documents = exchange.requestObject.documents.map { document in
            Document(documentType: document.appleDocumentType, region: document.region,
                     attributes: document.requestedAttributes.map {
                Attribute(attributeType: $0.attributeType, intentToStore: $0.intentToStore,
                          ageAtLeastXArgument: $0.ageAtLeastXArgument)
            })
        }
    }
}

internal enum NativeWalletDiagnostics {
    private static let logger = Logger(subsystem: "id.trinsic.TrinsicUI", category: "NativeWallet")

    static func emit(_ code: NativeWalletDiagnostic.Code, documentType: String? = nil,
                     attributeType: String? = nil, isAvailable: Bool? = nil,
                     request: NativeWalletRequestSummary? = nil,
                     to handler: ((NativeWalletDiagnostic) -> Void)?) {
        let level: NativeWalletDiagnostic.Level
        switch code {
        case .requestParsed, .availabilityChecked, .documentSelected: level = .info
        case .noSupportedDocuments: level = .error
        default: level = .warning
        }
        let diagnostic = NativeWalletDiagnostic(code: code,
            level: level, documentType: documentType, attributeType: attributeType,
            isAvailable: isAvailable, request: request)
        if diagnostic.level == .error {
            logger.error("Native Wallet: \(code.rawValue, privacy: .public)")
        } else if diagnostic.level == .info {
            // Request metadata is delivered only to the explicit callback.
            logger.info("Native Wallet: \(code.rawValue, privacy: .public); document=\(documentType ?? "", privacy: .private); available=\(isAvailable.map(String.init) ?? "", privacy: .public)")
        } else {
            // Backend-provided type names remain private in system logs.
            logger.warning("Native Wallet: \(code.rawValue, privacy: .public); document=\(documentType ?? "", privacy: .private); attribute=\(attributeType ?? "", privacy: .private)")
        }
        handler?(diagnostic)
    }
}

internal enum NativeWalletBase64 {
    /// Accept standard base64 and base64url, padded or unpadded, without ignoring invalid bytes.
    static func decode(_ value: String) throws -> Data {
        let payload = value.prefix { $0 != "=" }
        let padding = value.dropFirst(payload.count)
        guard !payload.isEmpty, padding.count <= 2, padding.allSatisfy({ $0 == "=" }),
              payload.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || [43, 47, 45, 95].contains($0) }),
              payload.count % 4 != 1 else { throw TrinsicWalletError.invalidRequest }
        let normalized = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let requiredPadding = (4 - normalized.count % 4) % 4
        guard padding.isEmpty || (padding.count == requiredPadding && value.count % 4 == 0),
              let data = Data(base64Encoded: normalized + String(repeating: "=", count: requiredPadding)),
              data.base64EncodedString() == normalized + String(repeating: "=", count: requiredPadding) else {
            throw TrinsicWalletError.invalidRequest
        }
        return data
    }
}

internal enum NativeWalletRequestParser {
    static func parse(_ encoded: String) throws -> ParsedExchangeRequest {
        let outer = try JSONDecoder().decode(NativeWalletChallenge.self,
            from: NativeWalletBase64.decode(encoded)).request
        guard outer.type == "mdlRequest" else {
            throw ExchangeRequestTransformerError.unsupportedExchangeType(outer.type)
        }
        guard outer.platform == "apple-wallet" else {
            throw ExchangeRequestTransformerError.unsupportedPlatform(outer.platform)
        }
        guard outer.exchangeMechanism == "NativeApp" else {
            throw ExchangeRequestTransformerError.unsupportedExchangeType(outer.exchangeMechanism)
        }
        let body = try JSONDecoder().decode(ExchangeRequestBody.self, from: Data(outer.requestObject.utf8))
        guard !outer.exchangeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !body.merchantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !body.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExchangeRequestTransformerError.invalidRequestData
        }
        _ = try NativeWalletBase64.decode(body.nonce)
        return ParsedExchangeRequest(exchangeId: outer.exchangeId, type: outer.type, platform: outer.platform,
            exchangeMechanism: outer.exchangeMechanism, requestObject: body)
    }
}

/// Select a complete request before decoding its schema or transaction binding.
private struct NativeWalletChallenge: Decodable {
    let request: ExchangeRequest

    private enum CodingKeys: String, CodingKey { case v1 }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // v1 is required. Other versions and unversioned sibling fields are ignored.
        guard container.contains(.v1) else {
            throw ExchangeRequestTransformerError.unsupportedChallengeVersion
        }
        request = try container.decode(ExchangeRequest.self, forKey: .v1)
    }
}
