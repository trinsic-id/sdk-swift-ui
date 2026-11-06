import XCTest
@testable import TrinsicUI

final class NativeWalletDiagnosticTests: XCTestCase {
    func testSummaryPreservesVersionedConfigurationWithoutSecretsOrUnknownProperties() throws {
        let nonce = Data("private-nonce-value".utf8).base64EncodedString()
        var document = walletDocument("NationalIDCard", region: "JP", attributes: [
            ["attributeType": "AgeAtLeastX", "intentToStore": 30, "ageAtLeastXArgument": 21,
             "privateAttribute": "secret-attribute"]
        ])
        document["privateDocument"] = "secret-document"
        let unversioned = try walletChallenge(documents: [document, walletDocument("DriversLicense")],
            bodyChanges: ["nonce": nonce, "merchantId": "merchant.test?~😀", "teamId": "TEAM123",
                          "privateBody": "secret-body"],
            envelopeChanges: ["exchangeId": "exchange123", "privateEnvelope": "secret-envelope"], versioned: false)
        let challenge = try walletVersionedChallenge(unversioned,
            siblings: ["v2": ["secret": "future-secret"], "exchangeId": "legacy-secret"])
        let parsed = try NativeWalletRequestParser.parse(challenge)
        let summary = try NativeWalletRequestSummary(exchange: parsed)
        XCTAssertEqual(summary.version, "v1")
        XCTAssertEqual(summary.exchangeId, "exchange123")
        XCTAssertEqual(summary.merchantId, "merchant.test?~😀")
        XCTAssertEqual(summary.teamId, "TEAM123")
        XCTAssertEqual(summary.nonceByteCount, 19)
        XCTAssertEqual(summary.documents.map(\.documentType), ["NationalIDCard", "DriversLicense"])
        XCTAssertEqual(summary.documents[0].region, "JP")
        XCTAssertEqual(summary.documents[0].attributes[0].attributeType, "AgeAtLeastX")
        XCTAssertEqual(summary.documents[0].attributes[0].intentToStore, 30)
        XCTAssertEqual(summary.documents[0].attributes[0].ageAtLeastXArgument, 21)
        let output = String(reflecting: summary)
        for secret in [nonce, "private-nonce-value", "secret-attribute", "secret-document", "secret-body",
                       "secret-envelope", "future-secret", "legacy-secret", unversioned, challenge] {
            XCTAssertFalse(output.contains(secret), "Diagnostic leaked \(secret)")
        }
    }

    func testLegacySingleDocumentShapeHasTheSameSummary() throws {
        let single = try NativeWalletRequestSummary(exchange: NativeWalletRequestParser.parse(walletChallenge()))
        let alternatives = try NativeWalletRequestSummary(exchange: NativeWalletRequestParser.parse(
            walletChallenge(documents: [walletDocument("DriversLicense")])))
        XCTAssertEqual(single, alternatives)
    }
}
