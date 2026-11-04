import Foundation
import OSLog

/// Structural diagnostics only: never contains a nonce, credential, or response token.
public struct NativeWalletDiagnostic: Equatable, Sendable {
    public enum Code: String, Sendable {
        case unsupportedDocumentType, documentUnavailableOnOS, selectingSingleDocument, noSupportedDocuments
    }
    public enum Level: String, Sendable { case warning, error }
    public let code: Code
    public let level: Level
    public let documentType: String?
}

internal enum NativeWalletDiagnostics {
    private static let logger = Logger(subsystem: "id.trinsic.TrinsicUI", category: "NativeWallet")

    static func emit(_ code: NativeWalletDiagnostic.Code, documentType: String? = nil,
                     to handler: ((NativeWalletDiagnostic) -> Void)?) {
        let diagnostic = NativeWalletDiagnostic(code: code,
            level: code == .noSupportedDocuments ? .error : .warning, documentType: documentType)
        if diagnostic.level == .error {
            logger.error("Native Wallet: \(code.rawValue, privacy: .public)")
        } else {
            // Backend-provided type names remain private in system logs.
            logger.warning("Native Wallet: \(code.rawValue, privacy: .public); document=\(documentType ?? "", privacy: .private)")
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
              payload.count % 4 != 1 else { throw TrinsicMdlError.invalidRequest }
        let normalized = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let requiredPadding = (4 - normalized.count % 4) % 4
        guard padding.isEmpty || (padding.count == requiredPadding && value.count % 4 == 0),
              let data = Data(base64Encoded: normalized + String(repeating: "=", count: requiredPadding)),
              data.base64EncodedString() == normalized + String(repeating: "=", count: requiredPadding) else {
            throw TrinsicMdlError.invalidRequest
        }
        return data
    }
}

internal enum NativeWalletRequestParser {
    static func parse(_ encoded: String) throws -> ParsedExchangeRequest {
        let outer = try JSONDecoder().decode(ExchangeRequest.self, from: NativeWalletBase64.decode(encoded))
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
