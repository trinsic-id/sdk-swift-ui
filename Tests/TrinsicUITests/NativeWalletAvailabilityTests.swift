#if os(iOS) && !targetEnvironment(macCatalyst)
import PassKit
import XCTest
@testable import TrinsicUI

@MainActor
final class NativeWalletAvailabilityTests: XCTestCase {
    func testDeniedCompositeUsesSameCompleteAlternativesForProbeAndExchange() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        let spy = AlternativeControllerSpy()
        spy.availability = { $0 is PKIdentityDriversLicenseDescriptor }
        spy.asynchronousChecks = true
        var diagnostics: [NativeWalletDiagnostic] = []
        let client = TrinsicCredentials(controller: spy) {
            XCTAssertTrue(Thread.isMainThread, "SDK callbacks stay on its main actor")
            diagnostics.append($0)
        }
        let challenge = try alternatives()
        let available = try await client.canRequestDocument(challenge)
        XCTAssertTrue(available)
        XCTAssertNil(spy.request)
        XCTAssertEqual(spy.checked.count, 3)
        await expectWalletCancellation(client, challenge)
        XCTAssertEqual(spy.checked.count, 6)
        let composite = try XCTUnwrap(spy.checked[3] as? PKIdentityAnyOfDescriptor)
        let request = try XCTUnwrap(spy.request)
        XCTAssertTrue(spy.checked[4] === composite.descriptors[0])
        XCTAssertTrue(spy.checked[5] === composite.descriptors[1])
        XCTAssertTrue(request.descriptor === composite.descriptors[1], "All fields and storage intents must be preserved")
        XCTAssertEqual(request.descriptor?.elements.map(\.description).sorted(),
                       [PKIdentityElement.givenName, .familyName].map(\.description).sorted())
        XCTAssertEqual(request.merchantIdentifier, "merchant.test")
        XCTAssertEqual(request.nonce, walletNonce)
        let checks = diagnostics.filter { $0.code == .availabilityChecked }
        XCTAssertEqual(checks.map(\.documentType), ["AnyOf", "PhotoID", "DriversLicense", "AnyOf", "PhotoID", "DriversLicense"])
        XCTAssertEqual(checks.map(\.isAvailable), [false, false, true, false, false, true])
        XCTAssertTrue(checks.allSatisfy { $0.level == .info })
        XCTAssertEqual(diagnostics.filter { $0.code == .documentSelected }.map(\.documentType), ["DriversLicense"])
        let summary = try XCTUnwrap(diagnostics.first?.request)
        XCTAssertEqual(diagnostics.first?.code, .requestParsed)
        XCTAssertEqual(summary.documents.map(\.documentType), ["PhotoID", "DriversLicense"])
        XCTAssertEqual(summary.documents[1].attributes.map(\.intentToStore), [30, -1])
    }

    func testSuccessfulCompositeRetainsAllAlternatives() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        let spy = AlternativeControllerSpy()
        var diagnostics: [NativeWalletDiagnostic] = []
        let client = TrinsicCredentials(controller: spy) { diagnostics.append($0) }
        let challenge = try alternatives()
        let available = try await client.canRequestDocument(challenge)
        XCTAssertTrue(available)
        await expectWalletCancellation(client, challenge)
        XCTAssertEqual(spy.checked.count, 2)
        let submitted = try XCTUnwrap(spy.request?.descriptor as? PKIdentityAnyOfDescriptor)
        XCTAssertTrue(submitted === spy.checked[1])
        XCTAssertEqual(submitted.descriptors.count, 2)
        XCTAssertFalse(diagnostics.contains { $0.code == .selectingSingleDocument })
        XCTAssertEqual(diagnostics.filter { $0.code == .documentSelected }.map(\.documentType), ["AnyOf"])
    }

    func testFallbackUsesBackendOrderWithoutHardcodingDriversLicense() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        let spy = AlternativeControllerSpy()
        spy.availability = { !($0 is PKIdentityAnyOfDescriptor) }
        await expectWalletCancellation(TrinsicCredentials(controller: spy), try alternatives())
        XCTAssertEqual(spy.checked.count, 2)
        XCTAssertTrue(spy.request?.descriptor is PKIdentityPhotoIDDescriptor)
        XCTAssertTrue(spy.request?.descriptor === spy.checked[1])
    }

    func testAllDeniedAlternativesReturnFalseAndNeverPresent() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        let spy = AlternativeControllerSpy()
        spy.availability = { _ in false }
        var diagnostics: [NativeWalletDiagnostic] = []
        let client = TrinsicCredentials(controller: spy) { diagnostics.append($0) }
        let challenge = try alternatives()
        let available = try await client.canRequestDocument(challenge)
        XCTAssertFalse(available)
        do {
            _ = try await client.performCredentialExchange(challenge)
            XCTFail("No alternative was approved")
        } catch CredentialExchangeError.documentRequestUnavailable { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(spy.checked.count, 6)
        XCTAssertNil(spy.request)
        XCTAssertFalse(diagnostics.contains { $0.code == .documentSelected })
    }

    func testExchangeRechecksPreviouslyAvailableAlternative() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        let spy = AlternativeControllerSpy()
        spy.availability = { $0 is PKIdentityDriversLicenseDescriptor }
        let client = TrinsicCredentials(controller: spy)
        let challenge = try alternatives()
        let available = try await client.canRequestDocument(challenge)
        XCTAssertTrue(available)
        spy.availability = { _ in false }
        do {
            _ = try await client.performCredentialExchange(challenge)
            XCTFail("An earlier probe must not authorize a newly denied request")
        } catch CredentialExchangeError.documentRequestUnavailable { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(spy.checked.count, 6)
        XCTAssertNil(spy.request)
    }

    func testCancellationAtEveryPreflightStageStopsBothPublicAPIs() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Composite descriptors require iOS 26") }
        for probeOnly in [true, false] {
            for cancelAt in 1...3 {
                let spy = AlternativeControllerSpy()
                let client = TrinsicCredentials(controller: spy)
                let challenge = try alternatives()
                let task = Task {
                    if probeOnly { _ = try await client.canRequestDocument(challenge) }
                    else { _ = try await client.performCredentialExchange(challenge) }
                }
                spy.availability = { descriptor in
                    if spy.checked.count == cancelAt { task.cancel() }
                    return descriptor is PKIdentityDriversLicenseDescriptor
                }
                do { try await task.value; XCTFail("Expected cancellation at check \(cancelAt)") }
                catch is CancellationError { }
                catch { XCTFail("Unexpected error: \(error)") }
                XCTAssertEqual(spy.checked.count, cancelAt)
                XCTAssertNil(spy.request)
            }
        }
    }

    func testCancellationFromDiagnosticsCannotProceedToPresentation() async throws {
        for event: NativeWalletDiagnostic.Code in [.availabilityChecked, .documentSelected] {
            let spy = AlternativeControllerSpy()
            var cancel: () -> Void = {}
            let client = TrinsicCredentials(controller: spy) {
                if $0.code == event { cancel() }
            }
            let challenge = try walletChallenge()
            let task = Task { try await client.performCredentialExchange(challenge) }
            cancel = { task.cancel() }
            do { _ = try await task.value; XCTFail("Expected cancellation from \(event)") }
            catch is CancellationError { }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(spy.checked.count, 1)
            XCTAssertNil(spy.request)
        }
    }

    private func alternatives() throws -> String {
        try walletChallenge(documents: [walletDocument("PhotoID"), walletDocument("DriversLicense", attributes: [
            ["attributeType": "GivenName", "intentToStore": 30],
            ["attributeType": "FamilyName", "intentToStore": -1]
        ])])
    }

    private func expectWalletCancellation(_ client: TrinsicCredentials, _ challenge: String,
                                          file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await client.performCredentialExchange(challenge); XCTFail("Spy cancels without accessing an ID", file: file, line: line) }
        catch CredentialExchangeError.documentRequestFailed(let error) {
            XCTAssertEqual((error as NSError).domain, PKIdentityErrorDomain, file: file, line: line)
            XCTAssertEqual((error as NSError).code, PKIdentityError.Code.cancelled.rawValue, file: file, line: line)
        } catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }
}

private final class AlternativeControllerSpy: PKIdentityAuthorizationController {
    var request: PKIdentityRequest?
    var checked: [any PKIdentityDocumentDescriptor] = []
    var availability: (any PKIdentityDocumentDescriptor) -> Bool = { _ in true }
    var asynchronousChecks = false

    override func checkCanRequestDocument(_ descriptor: any PKIdentityDocumentDescriptor, completion: @escaping @Sendable (Bool) -> Void) {
        checked.append(descriptor)
        let available = availability(descriptor)
        if asynchronousChecks { DispatchQueue.global().async { completion(available) } }
        else { completion(available) }
    }

    override func requestDocument(_ request: PKIdentityRequest, completion: @escaping (PKIdentityDocument?, (any Error)?) -> Void) {
        self.request = request
        completion(nil, NSError(domain: PKIdentityErrorDomain, code: PKIdentityError.Code.cancelled.rawValue))
    }
}
#endif
