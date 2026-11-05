import XCTest
@testable import TrinsicUI

final class NativeWalletContractTests: XCTestCase {
    func testBackendChallengesMatchSharedContract() throws {
        let fixtures = try NativeWalletContract.load()
        XCTAssertEqual(fixtures.map(\.name), ["mdl", "photo-id", "photo-id-or-mdl"])
        for fixture in fixtures {
            let request = try NativeWalletRequestParser.parse(walletVersionedChallenge(fixture.challenge))
            let expected = fixture.expected
            XCTAssertEqual(request.exchangeId, expected.exchangeId, fixture.name)
            XCTAssertEqual(request.type, "mdlRequest", fixture.name)
            XCTAssertEqual(request.platform, "apple-wallet", fixture.name)
            XCTAssertEqual(request.exchangeMechanism, "NativeApp", fixture.name)
            XCTAssertEqual(request.requestObject.merchantId, expected.merchantId, fixture.name)
            XCTAssertEqual(request.requestObject.teamId, expected.teamId, fixture.name)
            XCTAssertEqual(try NativeWalletBase64.decode(request.requestObject.nonce), Data(expected.nonce), fixture.name)
            let documents = request.requestObject.documents
            XCTAssertEqual(documents.count, expected.documents.count, fixture.name)
            XCTAssertEqual(request.requestObject.documentRequests == nil, expected.documents.count == 1, fixture.name)
            for (document, expectedDocument) in zip(documents, expected.documents) {
                XCTAssertEqual(document.appleDocumentType, expectedDocument.appleDocumentType, fixture.name)
                XCTAssertNil(document.region, fixture.name)
                XCTAssertEqual(document.requestedAttributes.count, expectedDocument.requestedAttributes.count, fixture.name)
                for (attribute, expectedAttribute) in zip(document.requestedAttributes, expectedDocument.requestedAttributes) {
                    XCTAssertEqual(attribute.attributeType, expectedAttribute.attributeType, fixture.name)
                    XCTAssertEqual(attribute.intentToStore, expectedAttribute.intentToStore, fixture.name)
                    XCTAssertEqual(attribute.ageAtLeastXArgument, expectedAttribute.ageAtLeastXArgument, fixture.name)
                }
            }
        }
    }
}

// The same fixture is checked against Connect's request builder in
// Tests/UnitTests/AppleWalletNativeContractTests.cs. See Fixtures/README.md.
struct NativeWalletContract: Decodable {
    let name: String
    let challenge: String
    let expected: Expected

    struct Expected: Decodable {
        let exchangeId: String
        let merchantId: String
        let teamId: String
        let nonce: [UInt8]
        let documents: [Document]
    }

    struct Document: Decodable {
        let appleDocumentType: String
        let requestedAttributes: [Attribute]
    }

    struct Attribute: Decodable {
        let attributeType: String
        let intentToStore: Int
        let ageAtLeastXArgument: Int?
    }

    static func load() throws -> [Self] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-wallet-contract", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}
