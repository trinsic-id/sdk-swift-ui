import Foundation
import XCTest
@testable import TrinsicUI

final class NativeChallengeVersionTests: XCTestCase {
    func testProductionParserMatchesV1SelectionContract() throws {
        // The shared fixture also describes hypothetical SDKs with v2/v10 support.
        // This SDK implements v1 only; exercise those inputs separately below.
        for fixture in try NativeChallengeFixture.load() where fixture.supportedVersions == ["v1"] {
            var actualError: String?
            do {
                let request = try NativeWalletRequestParser.parse(fixture.challenge)
                XCTAssertEqual(request.exchangeId, "dd9b5ed1-447b-4e31-b4a6-b7ea8527ee93", fixture.name)
                XCTAssertEqual(request.requestObject.nonce, "AH+A/v8=", fixture.name)
            } catch ExchangeRequestTransformerError.unsupportedChallengeVersion {
                actualError = "unsupported_challenge_version"
            } catch {
                actualError = "invalid_challenge"
            }
            let expectedError = fixture.selectedVersion == "legacy" ? "unsupported_challenge_version" : fixture.expectedError
            XCTAssertEqual(actualError, expectedError, fixture.name)
        }
    }

    func testFutureVersionsDoNotChangeV1Selection() throws {
        for fixture in try NativeChallengeFixture.load() where fixture.supportedVersions != ["v1"] {
            if fixture.name == "malformed-unselected-supported-version" {
                // v1 is malformed, while v2 is valid but unsupported by this SDK.
                XCTAssertThrowsError(try NativeWalletRequestParser.parse(fixture.challenge), fixture.name)
            } else {
                // Ignore v2/v10 even when their bodies are malformed or ordered first.
                let request = try NativeWalletRequestParser.parse(fixture.challenge)
                XCTAssertEqual(request.exchangeId, "dd9b5ed1-447b-4e31-b4a6-b7ea8527ee93", fixture.name)
            }
        }
    }

    func testHybridSelectsAllBindingAndDocumentFieldsFromV1() throws {
        let v1 = try walletChallenge(documents: [walletDocument("PhotoID")],
            bodyChanges: ["nonce": "AQID", "merchantId": "merchant.v1", "teamId": "TEAMV1"],
            envelopeChanges: ["exchangeId": "v1-exchange"], versioned: false)
        let legacy = try envelope(walletChallenge(versioned: false))
        let request = try NativeWalletRequestParser.parse(walletVersionedChallenge(v1, siblings: legacy))
        XCTAssertEqual(request.exchangeId, "v1-exchange")
        XCTAssertEqual(request.requestObject.nonce, "AQID")
        XCTAssertEqual(request.requestObject.merchantId, "merchant.v1")
        XCTAssertEqual(request.requestObject.teamId, "TEAMV1")
        XCTAssertEqual(request.requestObject.documents.map(\.appleDocumentType), ["PhotoID"])

        let malformedLegacy = legacy.mapValues { _ in NSNull() }
        XCTAssertEqual(try NativeWalletRequestParser.parse(
            walletVersionedChallenge(v1, siblings: malformedLegacy)).exchangeId, "v1-exchange")
    }

    func testMalformedSelectedVersionNeverFallsBackToLegacy() throws {
        let legacy = try envelope(walletChallenge(versioned: false))
        let invalid: [Any] = [NSNull(), false, 1, "not-a-request", [], [:]]
        for value in invalid {
            var hybrid = legacy
            hybrid["v1"] = value
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(challenge(hybrid))) { error in
                XCTAssertTrue(error is DecodingError, "Unexpected error: \(error)")
            }
        }
        for key in ["exchangeId", "type", "platform", "exchangeMechanism", "requestObject"] {
            var selected = legacy
            selected.removeValue(forKey: key)
            var hybrid = legacy
            hybrid["v1"] = selected
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(challenge(hybrid)), key)
        }
    }

    func testSelectedVersionUsesExistingEnvelopeAndBodyValidation() throws {
        let legacy = try envelope(walletChallenge(versioned: false))
        let invalidEnvelopes = [["type": "other"], ["platform": "google-wallet"],
            ["exchangeMechanism": "DigitalCredentialsApi"], ["exchangeId": " "], ["requestObject": "not-json"]]
        for changes in invalidEnvelopes {
            let v1 = try walletChallenge(envelopeChanges: changes, versioned: false)
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletVersionedChallenge(v1, siblings: legacy)))
        }
        let invalidBodies: [[String: Any]] = [["nonce": "bad!"], ["merchantId": ""], ["teamId": "\n"],
            ["requestedAttributes": "invalid"], ["documentRequests": [walletDocument("DriversLicense")]]]
        for changes in invalidBodies {
            let v1 = try walletChallenge(bodyChanges: changes, versioned: false)
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(walletVersionedChallenge(v1, siblings: legacy)))
        }
    }

    func testMissingV1RejectsLegacyAndOtherVersionKeys() throws {
        let legacy = try envelope(walletChallenge(versioned: false))
        for value in [[:], legacy] {
            XCTAssertThrowsError(try NativeWalletRequestParser.parse(challenge(value))) { error in
                guard case ExchangeRequestTransformerError.unsupportedChallengeVersion = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        for key in ["v0", "v01", "v-1", "v+1", "v1beta", "V1", "v1\n", "v1\r\n", "v١", "v１",
                    "v2", "v10", "v" + String(repeating: "9", count: 100)] {
            var hybrid = legacy
            hybrid[key] = NSNull()
            for value in [[key: NSNull()] as [String: Any], hybrid] {
                XCTAssertThrowsError(try NativeWalletRequestParser.parse(challenge(value)), key) { error in
                    guard case ExchangeRequestTransformerError.unsupportedChallengeVersion = error else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                }
            }
        }
    }

    func testVersionedChallengeAcceptsBothBase64AlphabetsAndPadding() throws {
        let encoded = try NativeWalletBase64.decode(walletChallenge(
            bodyChanges: ["merchantId": "merchant.test?~😀", "teamId": "TEAMé"])).base64EncodedString()
        let url = encoded.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        for value in [encoded, url, encoded.replacingOccurrences(of: "=", with: ""), url.replacingOccurrences(of: "=", with: "")] {
            let request = try NativeWalletRequestParser.parse(value)
            XCTAssertEqual(request.requestObject.merchantId, "merchant.test?~😀")
            XCTAssertEqual(request.requestObject.teamId, "TEAMé")
            XCTAssertEqual(try NativeWalletBase64.decode(request.requestObject.nonce), walletNonce)
        }
    }

    private func envelope(_ encoded: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: NativeWalletBase64.decode(encoded)) as? [String: Any])
    }

    private func challenge(_ envelope: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: envelope).base64EncodedString()
    }
}

struct NativeChallengeFixture: Decodable {
    let name: String
    let challenge: String
    let supportedVersions: [String]
    let selectedVersion: String?
    let expectedError: String?

    static func load() throws -> [Self] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "native-challenge-versions", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}

func walletVersionedChallenge(_ encoded: String, siblings: [String: Any] = [:]) throws -> String {
    var envelope = siblings
    envelope["v1"] = try JSONSerialization.jsonObject(with: NativeWalletBase64.decode(encoded))
    return try JSONSerialization.data(withJSONObject: envelope).base64EncodedString()
}
