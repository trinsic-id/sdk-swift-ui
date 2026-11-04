#if os(iOS) && !targetEnvironment(macCatalyst)
import PassKit
import XCTest
@testable import TrinsicUI

@MainActor
final class NativeWalletDescriptorTests: XCTestCase {
    func testLegacyLicenseRequestPreservesFieldsAndTransactionAtPassKitBoundary() async throws {
        let spy = NativeWalletControllerSpy()
        let client = TrinsicMdl(controller: spy)
        let request = try walletChallenge(bodyChanges: ["requestedAttributes": [
            ["attributeType": "GivenName", "intentToStore": 0],
            ["attributeType": "FamilyName", "intentToStore": -1],
            ["attributeType": "AgeAtLeastX", "intentToStore": 30, "ageAtLeastXArgument": 21]
        ]])
        let available = try await client.canRequestDriversLicense(request)
        XCTAssertTrue(available)
        await assertWalletCancellation(client, request)
        let submitted = try XCTUnwrap(spy.request)
        XCTAssertEqual(submitted.merchantIdentifier, "merchant.test")
        XCTAssertEqual(submitted.nonce, walletNonce)
        let descriptor = try XCTUnwrap(submitted.descriptor as? PKIdentityDriversLicenseDescriptor)
        XCTAssertEqual(descriptor.elements.count, 3)
        // PassKit returns opaque intent objects without public value accessors;
        // assert each requested element has an associated intent at the boundary.
        for element in [PKIdentityElement.givenName, .familyName, .age(atLeast: 21)] {
            XCTAssertNotNil(descriptor.intentToStore(element: element))
        }
        XCTAssertTrue(spy.checked[0] is PKIdentityDriversLicenseDescriptor)
    }

    func testPhotoIDUsesItsOwnDescriptorForAvailabilityAndPresentation() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Photo ID requires iOS 26") }
        let spy = NativeWalletControllerSpy()
        let client = TrinsicMdl(controller: spy)
        let request = try walletChallenge(bodyChanges: ["appleDocumentType": "PhotoID"])
        let available = try await client.canRequestDocument(request)
        XCTAssertTrue(available)
        await assertWalletCancellation(client, request)
        XCTAssertTrue(spy.checked[0] is PKIdentityPhotoIDDescriptor)
        XCTAssertTrue(spy.request?.descriptor is PKIdentityPhotoIDDescriptor)
    }

    func testJapanNationalIDPreservesRegionAndFields() async throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("National ID requires iOS 18") }
        let spy = NativeWalletControllerSpy()
        let client = TrinsicMdl(controller: spy)
        let request = try walletChallenge(documents: [walletDocument("NationalIDCard", region: "JP", attributes: [
            ["attributeType": "GivenName", "intentToStore": 0], ["attributeType": "DateOfBirth", "intentToStore": 0],
            ["attributeType": "Sex", "intentToStore": 0]
        ])])
        let available = try await client.canRequestDocument(request)
        XCTAssertTrue(available)
        await assertWalletCancellation(client, request)
        let descriptor = try XCTUnwrap(spy.request?.descriptor as? PKIdentityNationalIDCardDescriptor)
        XCTAssertEqual(descriptor.region, Locale.Region("JP"))
        XCTAssertEqual(descriptor.elements.count, 3)
        XCTAssertNotNil(descriptor.intentToStore(element: .sex))
        XCTAssertEqual((spy.checked[0] as? PKIdentityNationalIDCardDescriptor)?.region, Locale.Region("JP"))
    }

    func testUnknownDocumentIsFilteredBeforeCombiningKnownAlternatives() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        let spy = NativeWalletControllerSpy()
        var diagnostics: [NativeWalletDiagnostic] = []
        let client = TrinsicMdl(controller: spy) { diagnostics.append($0) }
        let request = try walletChallenge(documents: [
            ["appleDocumentType": "FutureID", "requestedAttributes": "future-schema"],
            walletDocument("DriversLicense"), walletDocument("PhotoID"), walletDocument("NationalIDCard", region: "JP")
        ])
        let available = try await client.canRequestDocument(request)
        XCTAssertTrue(available)
        await assertWalletCancellation(client, request)
        let descriptor = try XCTUnwrap(spy.request?.descriptor as? PKIdentityAnyOfDescriptor)
        XCTAssertEqual(descriptor.descriptors.count, 3)
        XCTAssertTrue(descriptor.descriptors[0] is PKIdentityDriversLicenseDescriptor)
        XCTAssertTrue(descriptor.descriptors[1] is PKIdentityPhotoIDDescriptor)
        XCTAssertTrue(descriptor.descriptors[2] is PKIdentityNationalIDCardDescriptor)
        XCTAssertEqual((spy.checked[0] as? PKIdentityAnyOfDescriptor)?.descriptors.count, 3)
        XCTAssertEqual(diagnostics.map(\.code), [.unsupportedDocumentType, .unsupportedDocumentType])
        XCTAssertTrue(diagnostics.allSatisfy { $0.level == .warning && $0.documentType == "FutureID" })
    }

    func testOldOSFiltersNewTypesAndStillPresentsLicense() async throws {
        let spy = NativeWalletControllerSpy()
        var diagnostics: [NativeWalletDiagnostic] = []
        let client = TrinsicMdl(controller: spy) { diagnostics.append($0) }
        client.capabilities = .init(version: .init(majorVersion: 17, minorVersion: 0, patchVersion: 0))
        let request = try walletChallenge(documents: [walletDocument("PhotoID"), walletDocument("NationalIDCard", region: "JP"), walletDocument("DriversLicense")])
        await assertWalletCancellation(client, request)
        XCTAssertTrue(spy.request?.descriptor is PKIdentityDriversLicenseDescriptor)
        XCTAssertEqual(diagnostics.map(\.code), [.documentUnavailableOnOS, .documentUnavailableOnOS])
    }

    func testPre26ChoosesFirstAvailableSupportedAlternative() async throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("National ID requires iOS 18") }
        let spy = NativeWalletControllerSpy()
        spy.availability = { $0 is PKIdentityNationalIDCardDescriptor }
        var diagnostics: [NativeWalletDiagnostic] = []
        let client = TrinsicMdl(controller: spy) { diagnostics.append($0) }
        client.capabilities = .init(version: .init(majorVersion: 18, minorVersion: 5, patchVersion: 0))
        let request = try walletChallenge(documents: [walletDocument("DriversLicense"), walletDocument("NationalIDCard", region: "JP")])
        let available = try await client.canRequestDocument(request)
        XCTAssertTrue(available)
        await assertWalletCancellation(client, request)
        XCTAssertTrue(spy.request?.descriptor is PKIdentityNationalIDCardDescriptor)
        XCTAssertEqual(diagnostics.map(\.code), [.selectingSingleDocument])
    }

    func testAllUnsupportedOrEmptyListsFailBeforeInvokingWallet() async throws {
        for documents in [[], [walletDocument("FutureID")], [walletDocument("PhotoID")]] {
            let spy = NativeWalletControllerSpy()
            var diagnostics: [NativeWalletDiagnostic] = []
            let client = TrinsicMdl(controller: spy) { diagnostics.append($0) }
            client.capabilities = .init(version: .init(majorVersion: 17, minorVersion: 0, patchVersion: 0))
            do {
                _ = try await client.performMdlExchange(walletChallenge(documents: documents))
                XCTFail("No supported document must fail")
            } catch ExchangeRequestTransformerError.noSupportedDocuments { }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertNil(spy.request)
            XCTAssertTrue(spy.checked.isEmpty)
            XCTAssertEqual(diagnostics.last?.code, .noSupportedDocuments)
            XCTAssertEqual(diagnostics.last?.level, .error)
        }
    }

    func testMalformedKnownRequestsDoNotSilentlyDropFieldsOrDocuments() async throws {
        let invalidAttributes: [[[String: Any]]] = [[],
            [["attributeType": "Unknown", "intentToStore": 0]],
            [["attributeType": "AgeAtLeastX", "intentToStore": 0]],
            [["attributeType": "AgeAtLeastX", "intentToStore": 0, "ageAtLeastXArgument": 126]],
            [["attributeType": "AgeAtLeastX", "intentToStore": 0, "ageAtLeastXArgument": 0]],
            [["attributeType": "GivenName", "intentToStore": -2]],
            [["attributeType": "GivenName", "intentToStore": 0, "ageAtLeastXArgument": 21]],
            [["attributeType": "Age", "intentToStore": 0], ["attributeType": "AgeAtLeastX", "intentToStore": 0, "ageAtLeastXArgument": 21]],
            [["attributeType": "GivenName", "intentToStore": 0], ["attributeType": "GivenName", "intentToStore": -1]]
        ]
        for attributes in invalidAttributes {
            let spy = NativeWalletControllerSpy()
            let client = TrinsicMdl(controller: spy)
            do {
                _ = try await client.performMdlExchange(walletChallenge(documents: [
                    walletDocument("DriversLicense", attributes: attributes), walletDocument("DriversLicense")]))
                XCTFail("Malformed known request must fail")
            } catch is ExchangeRequestTransformerError { }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertNil(spy.request)
            XCTAssertTrue(spy.checked.isEmpty)
        }
    }

    func testLegacyTypedHelperNeverSubstitutesLicenseForPhotoID() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Photo ID requires iOS 26") }
        let request = try NativeWalletRequestParser.parse(walletChallenge(bodyChanges: ["appleDocumentType": "PhotoID"]))
        XCTAssertThrowsError(try request.toDriversLicenseDescriptor())
    }

    func testAttributeMappingsForEachDocumentType() throws {
        var common = ["GivenName", "FamilyName", "Portrait", "Address", "DateOfBirth", "Age", "DocumentNumber"]
        if #available(iOS 17.2, *) { common.append("Sex") }
        let issued = ["IssuingAuthority", "DocumentIssueDate", "DocumentExpirationDate"]
        var license = common + issued + ["DrivingPrivileges"]
        if #available(iOS 17.2, *) { license.append("DocumentDHSComplianceStatus") }
        if #available(iOS 26.0, *) {
            license += ["Height", "Weight", "EyeColor", "HairColor", "OrganDonorStatus", "VeteranStatus"]
        }
        var cases: [(String, [String], String?)] = [("DriversLicense", license, nil)]
        if #available(iOS 18.0, *) { cases.append(("NationalIDCard", common, "JP")) }
        if #available(iOS 26.0, *) { cases.append(("PhotoID", common + issued, nil)) }
        for (type, fields, region) in cases {
            let attributes = fields.map { ["attributeType": $0, "intentToStore": 0] as [String: Any] }
            let request = try NativeWalletRequestParser.parse(walletChallenge(documents: [walletDocument(type, region: region, attributes: attributes)]))
            let descriptors = try request.toDocumentDescriptors()
            XCTAssertEqual(descriptors.count, 1)
            XCTAssertEqual(descriptors[0].elements.count, fields.count, type)
        }
    }

    func testRegionsAndDocumentSpecificFieldsAreValidated() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("National ID requires iOS 18") }
        for document in [
            walletDocument("DriversLicense", region: "JP"),
            walletDocument("NationalIDCard", region: "Japan"),
            walletDocument("NationalIDCard", region: "jp"),
            walletDocument("NationalIDCard", region: "JP", attributes: [["attributeType": "DrivingPrivileges", "intentToStore": 0]])
        ] {
            let request = try NativeWalletRequestParser.parse(walletChallenge(documents: [document]))
            XCTAssertThrowsError(try request.toDocumentDescriptors())
        }
        let unavailableElement = try NativeWalletRequestParser.parse(walletChallenge(bodyChanges: [
            "requestedAttributes": [["attributeType": "Sex", "intentToStore": 0]]
        ]))
        XCTAssertThrowsError(try ExchangeRequestTransformer.descriptors(from: unavailableElement,
            capabilities: .init(version: .init(majorVersion: 17, minorVersion: 0, patchVersion: 0)), diagnosticHandler: nil))
    }

    func testFalseAvailabilityStillAllowsWalletToReturnDefinitiveError() async throws {
        let spy = NativeWalletControllerSpy()
        spy.availability = { _ in false }
        let client = TrinsicMdl(controller: spy)
        let request = try walletChallenge()
        let available = try await client.canRequestDocument(request)
        XCTAssertFalse(available)
        await assertWalletCancellation(client, request)
        XCTAssertNotNil(spy.request)
    }

    func testCancellationBeforePresentationDoesNotInvokeController() async throws {
        let spy = NativeWalletControllerSpy()
        let client = TrinsicMdl(controller: spy)
        let request = try walletChallenge()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.performMdlExchange(request)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertNil(spy.request)
        XCTAssertTrue(spy.checked.isEmpty)
    }

    private func assertWalletCancellation(_ client: TrinsicMdl, _ request: String) async {
        do { _ = try await client.performMdlExchange(request); XCTFail("Spy cancels rather than accessing a real ID") }
        catch TrinsicMdlError.documentRequestFailed(let underlying) {
            XCTAssertEqual((underlying as NSError).domain, PKIdentityErrorDomain)
            XCTAssertEqual((underlying as NSError).code, PKIdentityError.Code.cancelled.rawValue)
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class NativeWalletControllerSpy: PKIdentityAuthorizationController {
    var request: PKIdentityRequest?
    var checked: [any PKIdentityDocumentDescriptor] = []
    var availability: (any PKIdentityDocumentDescriptor) -> Bool = { _ in true }

    override func checkCanRequestDocument(_ descriptor: any PKIdentityDocumentDescriptor, completion: @escaping (Bool) -> Void) {
        checked.append(descriptor)
        completion(availability(descriptor))
    }

    override func requestDocument(_ request: PKIdentityRequest, completion: @escaping (PKIdentityDocument?, (any Error)?) -> Void) {
        self.request = request
        completion(nil, NSError(domain: PKIdentityErrorDomain, code: PKIdentityError.Code.cancelled.rawValue))
    }
}
#endif
