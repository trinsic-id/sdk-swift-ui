import AuthenticationServices
import XCTest
@testable import TrinsicUI

@available(iOS 17.4, macOS 14.4, *)
@MainActor
final class LaunchSessionTests: XCTestCase {
    private let launchUrl = "https://verify.trinsic.id/?sessionId=123"
    private let callbackUrl = "https://example.com/session-complete"

    func testHttpsSessionReturnsSessionIdAndToken() async throws {
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { url, callback, completion in
            XCTAssertTrue(url.absoluteString.contains("launchMode=mobile"))
            XCTAssertEqual(callback.scheme, "https")
            XCTAssertEqual(callback.host, "example.com")
            XCTAssertEqual(callback.path, "/session-complete")
            return TestSession(completion: completion) {
                completion(URL(string: self.callbackUrl + "?sessionId=123&redirectToken=token&resultsAccessKey=legacy"), nil)
                return true
            }
        }
        let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
        XCTAssertEqual(result.sessionId, "123")
        XCTAssertEqual(result.redirectToken, "token")
        XCTAssertEqual(result.resultsAccessKey, "legacy")
        XCTAssertFalse(result.canceled)
    }

    func testRejectsMismatchedCallbackAndSession() async {
        for url in ["https://evil.example/session-complete?sessionId=123", callbackUrl + "?sessionId=other"] {
            let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
            client.makeAuthenticationSession = { _, _, completion in
                TestSession(completion: completion) { completion(URL(string: url), nil); return true }
            }
            do {
                _ = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
                XCTFail("Unexpectedly accepted \(url)")
            } catch {
                XCTAssertEqual((error as NSError).code, TrinsicErrorCode.unparsableResultUrl.rawValue)
            }
        }
    }

    func testProgrammaticCancelAndLateCompletionResumeOnlyOnce() async throws {
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        let started = expectation(description: "Session started")
        var completion: ASWebAuthenticationSession.CompletionHandler?
        client.makeAuthenticationSession = { _, _, handler in
            completion = handler
            return TestSession(completion: handler) { started.fulfill(); return true }
        }
        let task = Task { try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl) }
        await fulfillment(of: [started], timeout: 2)
        client.cancel()
        client.cancel()
        completion?(URL(string: callbackUrl + "?sessionId=123"), nil)
        let result = try await task.value
        XCTAssertTrue(result.canceled)
        XCTAssertNil(result.sessionId)
    }

    func testUserCancellation() async throws {
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { _, _, completion in
            TestSession(completion: completion) {
                completion(nil, ASWebAuthenticationSessionError(.canceledLogin))
                return true
            }
        }
        let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
        XCTAssertTrue(result.canceled)
    }

    func testFailureToStartThrowsInsteadOfHanging() async {
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { _, _, completion in TestSession(completion: completion) { false } }
        do {
            _ = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
            XCTFail("Expected start failure")
        } catch {
            XCTAssertEqual((error as NSError).code, TrinsicErrorCode.unknownError.rawValue)
        }
    }

    func testExistingCustomSchemeOverload() async throws {
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { _, callback, completion in
            XCTAssertEqual(callback.scheme, "example-app")
            return TestSession(completion: completion) {
                completion(URL(string: "example-app://session-complete?sessionId=123"), nil)
                return true
            }
        }
        let result = try await client.launchSession(launchUrl: launchUrl, callbackUrlScheme: "example-app")
        XCTAssertEqual(result.sessionId, "123")
    }
}

@available(iOS 17.4, macOS 14.4, *)
private final class TestSession: ASWebAuthenticationSession {
    private let onStart: () -> Bool
    init(completion: @escaping ASWebAuthenticationSession.CompletionHandler, onStart: @escaping () -> Bool) {
        self.onStart = onStart
        super.init(url: URL(string: "https://verify.trinsic.id")!, callback: .https(host: "example.com", path: "/session-complete"), completionHandler: completion)
    }
    override func start() -> Bool { onStart() }
    override func cancel() {}
}

private final class TestPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
