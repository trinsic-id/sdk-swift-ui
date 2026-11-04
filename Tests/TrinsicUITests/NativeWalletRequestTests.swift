import XCTest
@testable import TrinsicUI

final class NativeWalletRequestTests: XCTestCase {
    func testBase64AcceptsBothAlphabetsAndPaddingWithoutChangingBytes() throws {
        for length in 1...256 {
            let bytes = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 * 31 + 251) })
            let standard = bytes.base64EncodedString()
            let url = standard.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            for encoded in [standard, url, standard.replacingOccurrences(of: "=", with: ""), url.replacingOccurrences(of: "=", with: "")] {
                XCTAssertEqual(try NativeWalletBase64.decode(encoded), bytes)
            }
        }
        XCTAssertEqual(try NativeWalletBase64.decode("-_8"), Data([251, 255]))
    }

    func testBase64RejectsInvalidCharactersPaddingAndNoncanonicalBits() {
        for invalid in ["", "=", "A", "AA=", "AA===", "AA=A", "AA==\n", " A A==", "💳", "Zg!", "Zh==", "Zm9="] {
            XCTAssertThrowsError(try NativeWalletBase64.decode(invalid), invalid)
        }
    }

    func testBackendChallengePreservesTransactionAndUnicode() throws {
        let encoded = try walletChallenge(bodyChanges: ["merchantId": "merchant.test?~😀", "teamId": "TEAMé"])
        let request = try NativeWalletRequestParser.parse(encoded)
        XCTAssertEqual(request.exchangeId, "test-exchange")
        XCTAssertEqual(request.requestObject.merchantId, "merchant.test?~😀")
        XCTAssertEqual(request.requestObject.teamId, "TEAMé")
        XCTAssertEqual(try NativeWalletBase64.decode(request.requestObject.nonce), walletNonce)
        XCTAssertEqual(request.requestObject.documents[0].appleDocumentType, "DriversLicense")
    }

    func testEnvelopeAndBindingValidation() throws {
        for changes in [["type": "other"], ["platform": "google-wallet"], ["exchangeMechanism": "DigitalCredentialsApi"], ["exchangeId": " "]] {
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletChallenge(envelopeChanges: changes)))
        }
        for changes in [["nonce": ""], ["nonce": "bad!"], ["merchantId": ""], ["teamId": "\n"]] {
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletChallenge(bodyChanges: changes)))
        }
    }

    func testFutureDocumentSchemaDoesNotBreakKnownAlternative() throws {
        let request = try NativeWalletRequestParser.parse(walletChallenge(documents: [
            ["appleDocumentType": "FutureDocument", "requestedAttributes": ["future": true], "region": [1, 2]],
            walletDocument("DriversLicense")
        ]))
        XCTAssertEqual(request.requestObject.documents.count, 2)
        XCTAssertEqual(request.requestObject.documents[0].appleDocumentType, "FutureDocument")
        XCTAssertEqual(request.requestObject.documents[1].requestedAttributes[0].attributeType, "GivenName")
    }

    func testKnownMalformedDocumentAndAmbiguousFormatsAreRejected() throws {
        XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletChallenge(documents: [
            ["appleDocumentType": "DriversLicense", "requestedAttributes": "invalid"]
        ])))
        XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletChallenge(
            bodyChanges: ["documentRequests": [walletDocument("DriversLicense")]])))
        XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletChallenge(documents: [["missingType": true]])))
    }

    func testAgeArgumentAliasesAndEncoding() throws {
        for fields in ["\"ageAtLeastXArgument\":21", "\"ageOverArgument\":21", "\"ageAtLeastXArgument\":21,\"ageOverArgument\":21"] {
            let json = "{\"attributeType\":\"AgeAtLeastX\",\"intentToStore\":0,\(fields)}"
            let attribute = try JSONDecoder().decode(ExchangeRequestAttribute.self, from: Data(json.utf8))
            XCTAssertEqual(attribute.ageAtLeastXArgument, 21)
            XCTAssertEqual(attribute.ageOverArgument, 21)
            let encoded = String(decoding: try JSONEncoder().encode(attribute), as: UTF8.self)
            XCTAssertTrue(encoded.contains("ageAtLeastXArgument"))
            XCTAssertFalse(encoded.contains("ageOverArgument"))
        }
        let conflict = Data("{\"attributeType\":\"AgeAtLeastX\",\"intentToStore\":0,\"ageAtLeastXArgument\":21,\"ageOverArgument\":18}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ExchangeRequestAttribute.self, from: conflict))
    }

    func testResponseTokenIsUnchangedStandardBase64() throws {
        // Shared vector with Connect's AppleWalletNativeRequestTests
        // .DecodesSdkAndLegacyResponseWithoutChangingEncryptedBytes, which exercises
        // AppleWalletIntegration.DecodeNativeResponse (PR #5144).
        let encrypted = Data([0xa1, 0x64, 0x64, 0x61, 0x74, 0x61, 0x44, 0xff, 0xbf, 0xff, 0xfa])
        let result = MdlExchangeResult(exchangeId: "test-exchange", encryptedData: encrypted)
        XCTAssertEqual(result.exchangeId, "test-exchange")
        XCTAssertEqual(result.token, "oWRkYXRhRP+///o=")
        XCTAssertEqual(Data(base64Encoded: result.token), encrypted)
    }

    func testSingleAndMultipleDocumentBodiesRoundTrip() throws {
        for documents in [nil, [walletDocument("PhotoID"), walletDocument("NationalIDCard", region: "JP")]] {
            let request = try NativeWalletRequestParser.parse(walletChallenge(documents: documents))
            let encoded = try JSONEncoder().encode(request.requestObject)
            let decoded = try JSONDecoder().decode(ExchangeRequestBody.self, from: encoded)
            XCTAssertEqual(decoded.documents.map(\.appleDocumentType), request.requestObject.documents.map(\.appleDocumentType))
            XCTAssertEqual(decoded.documents.map(\.region), request.requestObject.documents.map(\.region))
            XCTAssertEqual(decoded.nonce, request.requestObject.nonce)
        }
    }
}

let walletNonce = Data([0, 127, 128, 254, 255])

func walletDocument(_ type: String, region: String? = nil, attributes: [[String: Any]]? = nil) -> [String: Any] {
    var value: [String: Any] = ["appleDocumentType": type,
        "requestedAttributes": attributes ?? [["attributeType": "GivenName", "intentToStore": 0]]]
    if let region { value["region"] = region }
    return value
}

func walletChallenge(documents: [[String: Any]]? = nil, bodyChanges: [String: Any] = [:],
                     envelopeChanges: [String: String] = [:]) throws -> String {
    var body: [String: Any] = ["nonce": walletNonce.base64EncodedString(), "merchantId": "merchant.test", "teamId": "TEAM123"]
    if let documents { body["documentRequests"] = documents }
    else { body.merge(walletDocument("DriversLicense")) { _, value in value } }
    body.merge(bodyChanges) { _, value in value }
    var envelope = ["type": "mdlRequest", "platform": "apple-wallet", "exchangeMechanism": "NativeApp",
        "exchangeId": "test-exchange", "requestObject": String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)]
    envelope.merge(envelopeChanges) { _, value in value }
    return try JSONSerialization.data(withJSONObject: envelope).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
