#if os(iOS) && !targetEnvironment(macCatalyst)
import PassKit
import XCTest
@testable import TrinsicUI

@MainActor
final class NativeWalletDescriptorTests: XCTestCase {
    func testSharedBackendChallengesReachPassKitWithExpectedDocumentsAndFields() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Photo ID and composite descriptors require iOS 26") }
        for fixture in try NativeWalletContract.load() {
            let challenge = try walletVersionedChallenge(fixture.challenge)
            let spy = NativeWalletControllerSpy()
            let client = TrinsicWallet(controller: spy)
            let available = try await client.canRequestDocument(challenge)
            XCTAssertTrue(available, fixture.name)
            await assertWalletCancellation(client, challenge)
            let request = try XCTUnwrap(spy.request)
            XCTAssertEqual(request.merchantIdentifier, fixture.expected.merchantId, fixture.name)
            XCTAssertEqual(request.nonce, Data(fixture.expected.nonce), fixture.name)
            let submitted = try XCTUnwrap(request.descriptor)
            let descriptors: [any PKIdentityDocumentDescriptor]
            if fixture.expected.documents.count > 1 {
                descriptors = try XCTUnwrap(submitted as? PKIdentityAnyOfDescriptor).descriptors
            } else {
                descriptors = [submitted]
            }
            XCTAssertEqual(descriptors.count, fixture.expected.documents.count, fixture.name)
            for (descriptor, expected) in zip(descriptors, fixture.expected.documents) {
                if expected.appleDocumentType == "PhotoID" {
                    XCTAssertTrue(descriptor is PKIdentityPhotoIDDescriptor, fixture.name)
                } else {
                    XCTAssertTrue(descriptor is PKIdentityDriversLicenseDescriptor, fixture.name)
                }
                assertElements(descriptor, [.givenName, .familyName, .dateOfBirth, .age(atLeast: 21)], fixture.name)
            }
        }
    }

    func testUnsupportedOrMalformedVersionFailsBeforeAvailabilityAndPresentation() async throws {
        for fixture in try NativeChallengeFixture.load()
            where fixture.supportedVersions == ["v1"]
                && (fixture.expectedError != nil || fixture.selectedVersion == "legacy") {
            for availabilityOnly in [true, false] {
                let spy = NativeWalletControllerSpy()
                let client = TrinsicWallet(controller: spy)
                do {
                    if availabilityOnly {
                        _ = try await client.canRequestDocument(fixture.challenge)
                    } else {
                        _ = try await client.performExchange(fixture.challenge)
                    }
                    XCTFail("Expected invalid challenge to fail: \(fixture.name)")
                } catch { }
                XCTAssertTrue(spy.checked.isEmpty, fixture.name)
                XCTAssertNil(spy.request, fixture.name)
            }
        }
    }

    func testLegacyLicenseRequestPreservesFieldsAndTransactionAtPassKitBoundary() async throws {
        let spy = NativeWalletControllerSpy()
        let client = TrinsicWallet(controller: spy)
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
        let client = TrinsicWallet(controller: spy)
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
        let client = TrinsicWallet(controller: spy)
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
        let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
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
        let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
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
        let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
        client.capabilities = .init(version: .init(majorVersion: 18, minorVersion: 5, patchVersion: 0))
        let request = try walletChallenge(documents: [walletDocument("DriversLicense"), walletDocument("NationalIDCard", region: "JP")])
        let available = try await client.canRequestDocument(request)
        XCTAssertTrue(available)
        await assertWalletCancellation(client, request)
        XCTAssertTrue(spy.request?.descriptor is PKIdentityNationalIDCardDescriptor)
        XCTAssertEqual(diagnostics.map(\.code), [.selectingSingleDocument, .selectingSingleDocument])
    }

    func testAllUnsupportedOrEmptyListsFailBeforeInvokingWallet() async throws {
        for documents in [[], [walletDocument("FutureID")], [walletDocument("PhotoID")]] {
            let spy = NativeWalletControllerSpy()
            var diagnostics: [NativeWalletDiagnostic] = []
            let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
            client.capabilities = .init(version: .init(majorVersion: 17, minorVersion: 0, patchVersion: 0))
            do {
                _ = try await client.performExchange(walletChallenge(documents: documents))
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
            let client = TrinsicWallet(controller: spy)
            do {
                _ = try await client.performExchange(walletChallenge(documents: [
                    walletDocument("DriversLicense", attributes: attributes), walletDocument("DriversLicense")]))
                XCTFail("Malformed known request must fail")
            } catch is ExchangeRequestTransformerError { }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertNil(spy.request)
            XCTAssertTrue(spy.checked.isEmpty)
        }
    }

    func testUnknownAttributeSkipsWholeAlternativeForAvailabilityAndPresentation() async throws {
        for unknownFirst in [true, false] {
            let spy = NativeWalletControllerSpy()
            var diagnostics: [NativeWalletDiagnostic] = []
            let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
            let attributes: [[String: Any]] = [
                ["attributeType": "GivenName", "intentToStore": 0],
                ["attributeType": "FutureField", "intentToStore": 0,
                 "ageAtLeastXArgument": ["future": true]]
            ]
            let unsupported = walletDocument("DriversLicense", attributes: unknownFirst ? Array(attributes.reversed()) : attributes)
            let supported = walletDocument("DriversLicense", attributes: [
                ["attributeType": "AgeAtLeastX", "intentToStore": 30, "ageAtLeastXArgument": 21]
            ])
            let request = try walletChallenge(documents: unknownFirst ? [unsupported, supported] : [supported, unsupported])
            let available = try await client.canRequestDocument(request)
            XCTAssertTrue(available)
            let checked = try XCTUnwrap(spy.checked.first as? PKIdentityDriversLicenseDescriptor)
            XCTAssertEqual(spy.checked.count, 1)
            XCTAssertEqual(checked.elements.count, 1)
            XCTAssertNotNil(checked.intentToStore(element: .age(atLeast: 21)))

            await assertWalletCancellation(client, request)
            let submitted = try XCTUnwrap(spy.request)
            let descriptor = try XCTUnwrap(submitted.descriptor as? PKIdentityDriversLicenseDescriptor)
            XCTAssertEqual(descriptor.elements.count, 1)
            XCTAssertNotNil(descriptor.intentToStore(element: .age(atLeast: 21)))
            XCTAssertEqual(submitted.nonce, walletNonce)
            XCTAssertEqual(submitted.merchantIdentifier, "merchant.test")
            XCTAssertEqual(diagnostics.map(\.code), [.unsupportedAttribute, .unsupportedAttribute])
            XCTAssertTrue(diagnostics.allSatisfy {
                $0.level == .warning && $0.documentType == "DriversLicense" && $0.attributeType == "FutureField"
            })
        }
    }

    func testOSUnavailableAndDocumentSpecificAttributesSkipWholeAlternatives() async throws {
        var cases: [(String, String, Int)] = [("DriversLicense", "Sex", 17), ("DriversLicense", "Height", 18)]
        if #available(iOS 18.0, *) { cases.append(("NationalIDCard", "DrivingPrivileges", 18)) }
        for (type, attribute, majorVersion) in cases {
            let spy = NativeWalletControllerSpy()
            var diagnostics: [NativeWalletDiagnostic] = []
            let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
            client.capabilities = .init(version: .init(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0))
            let request = try walletChallenge(documents: [
                walletDocument(type, attributes: [
                    ["attributeType": "GivenName", "intentToStore": 0],
                    ["attributeType": attribute, "intentToStore": 0]
                ]), walletDocument("DriversLicense", attributes: [["attributeType": "FamilyName", "intentToStore": 0]])
            ])
            let available = try await client.canRequestDocument(request)
            XCTAssertTrue(available)
            XCTAssertEqual(spy.checked.count, 1)
            await assertWalletCancellation(client, request)
            let descriptor = try XCTUnwrap(spy.request?.descriptor as? PKIdentityDriversLicenseDescriptor)
            XCTAssertEqual(descriptor.elements.count, 1)
            XCTAssertNotNil(descriptor.intentToStore(element: .familyName))
            XCTAssertEqual(diagnostics.map(\.code), [.unsupportedAttribute, .unsupportedAttribute])
            XCTAssertTrue(diagnostics.allSatisfy { $0.documentType == type && $0.attributeType == attribute })
        }
    }

    func testUnsupportedAttributesWithoutCompleteAlternativeFailBeforeWallet() async throws {
        let attributes: [[String: Any]] = [
            ["attributeType": "GivenName", "intentToStore": 0],
            ["attributeType": "FutureField", "intentToStore": 0]
        ]
        // Cover the legacy shape, a single alternative, and multiple alternatives.
        for documents in [nil, [walletDocument("DriversLicense", attributes: attributes)],
                          [walletDocument("DriversLicense", attributes: attributes), walletDocument("FutureID")]] {
            for availabilityOnly in [true, false] {
                let spy = NativeWalletControllerSpy()
                var diagnostics: [NativeWalletDiagnostic] = []
                let client = TrinsicWallet(controller: spy) { if $0.level != .info { diagnostics.append($0) } }
                let request = try walletChallenge(documents: documents,
                    bodyChanges: documents == nil ? ["requestedAttributes": attributes] : [:])
                do {
                    if availabilityOnly { _ = try await client.canRequestDocument(request) }
                    else { _ = try await client.performExchange(request) }
                    XCTFail("An incomplete document must never reach Wallet")
                } catch ExchangeRequestTransformerError.noSupportedDocuments { }
                catch { XCTFail("Unexpected error: \(error)") }
                XCTAssertNil(spy.request)
                XCTAssertTrue(spy.checked.isEmpty)
                XCTAssertEqual(diagnostics.first?.code, .unsupportedAttribute)
                XCTAssertEqual(diagnostics.last?.code, .noSupportedDocuments)
                XCTAssertEqual(diagnostics.last?.level, .error)
            }
        }
    }

    func testUnsupportedAttributesCannotMaskMalformedKnownRequirements() async throws {
        let invalidAttributes: [[[String: Any]]] = [
            [["attributeType": "AgeAtLeastX", "intentToStore": 0]],
            [["attributeType": "AgeAtLeastX", "intentToStore": 0, "ageAtLeastXArgument": 126]],
            [["attributeType": "GivenName", "intentToStore": -2]],
            [["attributeType": "GivenName", "intentToStore": 0, "ageAtLeastXArgument": 21]],
            [["attributeType": "Height", "intentToStore": 0, "ageAtLeastXArgument": 21]],
            [["attributeType": "FutureField", "intentToStore": -2]],
            [["attributeType": "Age", "intentToStore": 0], ["attributeType": "AgeAtLeastX", "intentToStore": 0, "ageAtLeastXArgument": 21]],
            [["attributeType": "GivenName", "intentToStore": 0], ["attributeType": "GivenName", "intentToStore": -1]]
        ]
        for invalid in invalidAttributes {
            for unknownFirst in [true, false] {
                let spy = NativeWalletControllerSpy()
                let client = TrinsicWallet(controller: spy)
                client.capabilities = .init(version: .init(majorVersion: 18, minorVersion: 0, patchVersion: 0))
                let unknown: [[String: Any]] = [["attributeType": "AnotherFutureField", "intentToStore": 0]]
                let request = try walletChallenge(documents: [
                    walletDocument("DriversLicense", attributes: unknownFirst ? unknown + invalid : invalid + unknown),
                    walletDocument("DriversLicense")
                ])
                do {
                    _ = try await client.performExchange(request)
                    XCTFail("An unsupported field must not hide an invalid known field")
                } catch ExchangeRequestTransformerError.invalidAttribute { }
                catch { XCTFail("Unexpected error: \(error)") }
                XCTAssertNil(spy.request)
                XCTAssertTrue(spy.checked.isEmpty)
            }
        }
    }

    func testLegacyTypedHelperNeverSubstitutesLicenseForPhotoID() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Photo ID requires iOS 26") }
        let request = try NativeWalletRequestParser.parse(walletChallenge(bodyChanges: ["appleDocumentType": "PhotoID"]))
        XCTAssertThrowsError(try request.toDriversLicenseDescriptor())
    }

    func testAttributeMappingsForEachDocumentType() throws {
        var common: [(String, PKIdentityElement)] = [
            ("GivenName", .givenName), ("FamilyName", .familyName), ("Portrait", .portrait),
            ("Address", .address), ("DateOfBirth", .dateOfBirth), ("Age", .age),
            ("DocumentNumber", .documentNumber)
        ]
        if #available(iOS 17.2, *) { common.append(("Sex", .sex)) }
        let issued: [(String, PKIdentityElement)] = [
            ("IssuingAuthority", .issuingAuthority), ("DocumentIssueDate", .documentIssueDate),
            ("DocumentExpirationDate", .documentExpirationDate)
        ]
        var license = common + issued + [("DrivingPrivileges", PKIdentityElement.drivingPrivileges)]
        if #available(iOS 17.2, *) { license.append(("DocumentDHSComplianceStatus", .documentDHSComplianceStatus)) }
        if #available(iOS 26.0, *) {
            license += [("Height", .height), ("Weight", .weight), ("EyeColor", .eyeColor),
                        ("HairColor", .hairColor), ("OrganDonorStatus", .organDonorStatus), ("VeteranStatus", .veteranStatus)]
        }
        var cases: [(String, [(String, PKIdentityElement)], String?)] = [("DriversLicense", license, nil)]
        if #available(iOS 18.0, *) { cases.append(("NationalIDCard", common, "JP")) }
        if #available(iOS 26.0, *) { cases.append(("PhotoID", common + issued, nil)) }
        for (type, fields, region) in cases {
            // Check each mapping independently: swapping two elements must fail even
            // when a request containing every supported element would have the same set.
            for (field, expected) in fields {
                let request = try NativeWalletRequestParser.parse(walletChallenge(documents: [
                    walletDocument(type, region: region, attributes: [["attributeType": field, "intentToStore": 0]])
                ]))
                let descriptors = try request.toDocumentDescriptors()
                XCTAssertEqual(descriptors.count, 1)
                let descriptor = try XCTUnwrap(descriptors.first)
                assertElements(descriptor, [expected], "\(type).\(field)")
            }
        }
    }

    func testAgeThresholdMapsToExactPassKitElementForEveryDocumentType() throws {
        var cases: [(String, String?)] = [("DriversLicense", nil)]
        if #available(iOS 18.0, *) { cases.append(("NationalIDCard", "JP")) }
        if #available(iOS 26.0, *) { cases.append(("PhotoID", nil)) }
        for (type, region) in cases {
            for age in [1, 18, 21, 125] {
                let request = try NativeWalletRequestParser.parse(walletChallenge(documents: [
                    walletDocument(type, region: region, attributes: [
                        ["attributeType": "AgeAtLeastX", "intentToStore": 0, "ageAtLeastXArgument": age]
                    ])
                ]))
                let descriptor = try XCTUnwrap(request.toDocumentDescriptors().first)
                assertElements(descriptor, [.age(atLeast: age)], "\(type), age \(age)")
                XCTAssertNotEqual(descriptor.elements.first?.description, PKIdentityElement.age.description)
                XCTAssertNotEqual(descriptor.elements.first?.description, PKIdentityElement.age(atLeast: age == 21 ? 18 : 21).description)
            }
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

    func testDeniedPreflightNeverRequestsDocumentForSingleCompositeOrLegacyAlternatives() async throws {
        for legacy in [false, true] {
            var requests = [try walletChallenge(),
                            try walletChallenge(documents: [walletDocument("DriversLicense"), walletDocument("DriversLicense")])]
            if !legacy {
                if #available(iOS 18.0, *) {
                    requests.append(try walletChallenge(documents: [walletDocument("NationalIDCard", region: "JP")]))
                }
                if #available(iOS 26.0, *) {
                    requests.append(try walletChallenge(documents: [walletDocument("PhotoID")]))
                    requests.append(try walletChallenge(documents: [walletDocument("PhotoID"), walletDocument("DriversLicense")]))
                }
            }
            for request in requests {
                let spy = NativeWalletControllerSpy()
                spy.availability = { _ in false }
                let client = TrinsicWallet(controller: spy)
                if legacy { client.capabilities = .init(version: .init(majorVersion: 17, minorVersion: 0, patchVersion: 0)) }
                // Call perform directly: callers must not need their own preflight to avoid a fatal OS assertion.
                do {
                    _ = try await client.performExchange(request)
                    XCTFail("A denied preflight must fail before requestDocument")
                } catch TrinsicWalletError.documentRequestUnavailable { }
                catch { XCTFail("Unexpected error: \(error)") }
                XCTAssertFalse(spy.checked.isEmpty)
                XCTAssertNil(spy.request)
            }
        }
    }

    func testCancellationBeforePresentationDoesNotInvokeController() async throws {
        let spy = NativeWalletControllerSpy()
        let client = TrinsicWallet(controller: spy)
        let request = try walletChallenge()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.performExchange(request)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertNil(spy.request)
        XCTAssertTrue(spy.checked.isEmpty)
    }

    func testPerformRechecksAvailabilityAfterEarlierSuccessfulProbe() async throws {
        let spy = NativeWalletControllerSpy()
        var checks = 0
        spy.availability = { _ in checks += 1; return checks == 1 }
        let client = TrinsicWallet(controller: spy)
        let request = try walletChallenge()
        let available = try await client.canRequestDocument(request)
        XCTAssertTrue(available)
        do {
            _ = try await client.performExchange(request)
            XCTFail("An earlier successful probe must not bypass the current denial")
        } catch TrinsicWalletError.documentRequestUnavailable { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(checks, 2)
        XCTAssertNil(spy.request)
    }

    func testCancellationDuringPreflightDoesNotBecomeAnAvailabilityFailure() async throws {
        let spy = NativeWalletControllerSpy()
        let client = TrinsicWallet(controller: spy)
        let request = try walletChallenge()
        let task = Task { try await client.performExchange(request) }
        spy.availability = { _ in task.cancel(); return false }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(spy.checked.count, 1)
        XCTAssertNil(spy.request)
    }

    private func assertElements(_ descriptor: any PKIdentityDocumentDescriptor, _ expected: [PKIdentityElement],
                                _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        // PassKit exposes no element identifier/value equality. Compare its public
        // descriptions with fresh native elements on the same OS, including age values.
        // intentToStore is insufficient: it returns a default even for absent elements.
        XCTAssertEqual(descriptor.elements.map(\.description).sorted(), expected.map(\.description).sorted(),
                       message, file: file, line: line)
    }

    private func assertWalletCancellation(_ client: TrinsicWallet, _ request: String) async {
        do { _ = try await client.performExchange(request); XCTFail("Spy cancels rather than accessing a real ID") }
        catch TrinsicWalletError.documentRequestFailed(let underlying) {
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
