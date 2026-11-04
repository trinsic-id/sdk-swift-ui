import AuthenticationServices
import XCTest
@testable import TrinsicUI

@available(iOS 17.4, macOS 14.4, *)
@MainActor
final class LaunchSessionTests: XCTestCase {
    private let launchUrl = "https://verify.trinsic.id/start?sessionId=123"
    private let callbackUrl = "https://example.com/session-complete"

    func testHttpsSessionReturnsSessionIdAndToken() async throws {
        let returnedUrl = callbackUrl + "?sessionId=123&redirectToken=token&extra=a%2Fb#complete"
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { url, callback, completion in
            XCTAssertEqual(url.absoluteString, self.launchUrl)
            XCTAssertEqual(callback.scheme, "https")
            XCTAssertEqual(callback.host, "example.com")
            XCTAssertEqual(callback.path, "/session-complete")
            return TestSession(completion: completion) {
                completion(URL(string: returnedUrl), nil)
                return true
            }
        }
        let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
        XCTAssertEqual(result.sessionId, "123")
        XCTAssertEqual(result.redirectToken, "token")
        XCTAssertEqual(result.callbackUrl, returnedUrl)
        XCTAssertFalse(result.canceled)
    }

    func testLaunchQueryIsPassedThroughWithoutModification() async throws {
        for launchUrl in [
            "https://verify.trinsic.id/?sessionId=123&token=a%2Fb%2Bc%3D&state=a+b",
            "https://verify.trinsic.id/?sessionId=123&launchMode=web#continue"
        ] {
            let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
            client.makeAuthenticationSession = { url, _, completion in
                XCTAssertEqual(url.absoluteString, launchUrl)
                return TestSession(completion: completion) {
                    completion(URL(string: self.callbackUrl + "?sessionId=123"), nil)
                    return true
                }
            }
            let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
            XCTAssertEqual(result.sessionId, "123")
        }
    }

    func testRejectsInvalidLaunchSessionIdsBeforeOpeningBrowser() async {
        for useSchemeOnly in [false, true] {
            for query in ["", "?sessionId", "?sessionId=", "?SessionId=123", "#sessionId=123",
                          "?sessionId=123&sessionId=other", "?sessionId=123&sessionId=123"] {
                let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
                client.makeAuthenticationSession = { _, _, _ in
                    XCTFail("Invalid launch session ID should fail before creating the browser session")
                    throw TrinsicError.error(with: .unknownError)
                }
                let invalidLaunchUrl = "https://verify.trinsic.id/" + query
                do {
                    if useSchemeOnly {
                        _ = try await client.launchSession(launchUrl: invalidLaunchUrl, callbackUrlScheme: "example-app")
                    } else {
                        _ = try await client.launchSession(launchUrl: invalidLaunchUrl, callbackUrl: callbackUrl)
                    }
                    XCTFail("Unexpectedly accepted \(invalidLaunchUrl)")
                } catch {
                    XCTAssertEqual((error as NSError).code, TrinsicErrorCode.missingSessionId.rawValue, query)
                }
            }
        }
    }

    func testRejectsInvalidOrMismatchedReturnedSessionIds() async {
        for useSchemeOnly in [false, true] {
            for query in ["", "?sessionId", "?sessionId=", "?sessionId=other", "?sessionId=123&sessionId=other",
                          "?sessionId=123&sessionId=123", "?sessionId=123&session%49d=123", "?canceled=true"] {
                let returnedUrl = (useSchemeOnly ? "example-app://session-complete" : callbackUrl) + query
                let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
                client.makeAuthenticationSession = { _, _, completion in
                    TestSession(completion: completion) { completion(URL(string: returnedUrl), nil); return true }
                }
                do {
                    if useSchemeOnly {
                        _ = try await client.launchSession(launchUrl: launchUrl, callbackUrlScheme: "example-app")
                    } else {
                        _ = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
                    }
                    XCTFail("Unexpectedly accepted \(returnedUrl)")
                } catch {
                    XCTAssertEqual((error as NSError).code, TrinsicErrorCode.unparsableResultUrl.rawValue, query)
                }
            }
        }
    }

    func testSessionIdsMatchAfterPercentDecoding() async throws {
        let returnedUrl = callbackUrl + "?sessionId=abc%2f123"
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { _, _, completion in
            TestSession(completion: completion) { completion(URL(string: returnedUrl), nil); return true }
        }
        let result = try await client.launchSession(
            launchUrl: "https://verify.trinsic.id/?sessionId=abc%2F123", callbackUrl: callbackUrl)
        XCTAssertEqual(result.sessionId, "abc/123")
        XCTAssertEqual(result.callbackUrl, returnedUrl)
    }

    func testOptionalRedirectTokenAndIgnoredLegacyParameters() async throws {
        let cases: [(query: String, redirectToken: String?)] = [
            ("", nil),
            ("&redirectToken=token", "token"),
            ("&redirectToken", nil),
            ("&redirectToken=", nil),
            ("&success=not-a-bool&resultsAccessKey=legacy", nil),
            ("&redirectToken=one&redirectToken=two", "one"),
            ("&redirectToken=t%2B%3D#complete", "t+=")
        ]
        for testCase in cases {
            let returnedUrl = callbackUrl + "?sessionId=123" + testCase.query
            let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
            client.makeAuthenticationSession = { _, _, completion in
                TestSession(completion: completion) { completion(URL(string: returnedUrl), nil); return true }
            }
            let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
            XCTAssertEqual(result.sessionId, "123", testCase.query)
            XCTAssertEqual(result.redirectToken, testCase.redirectToken, testCase.query)
            XCTAssertEqual(result.callbackUrl, returnedUrl)
            XCTAssertFalse(result.canceled)
            XCTAssertFalse(result.responds(to: NSSelectorFromString("success")))
            XCTAssertFalse(result.responds(to: NSSelectorFromString("resultsAccessKey")))
        }
    }

    func testAcceptsNativeCallbackMatching() async throws {
        for (callbackUrl, returnedUrl) in [
            ("https://example.com/session%2Dcomplete", "https://example.com/session-complete?sessionId=123"),
            ("example-app://configured/path", "example-app://another-host/another-path?sessionId=123")
        ] {
            let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
            client.makeAuthenticationSession = { _, callback, completion in
                let url = URL(string: returnedUrl)!
                XCTAssertTrue(callback.nativeCallback.matchesURL(url))
                return TestSession(completion: completion) { completion(url, nil); return true }
            }
            let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
            XCTAssertEqual(result.callbackUrl, returnedUrl)
            XCTAssertEqual(result.sessionId, "123")
            XCTAssertNil(result.redirectToken)
        }
    }

    func testCallbackCancellationPreservesReturnedUrl() async throws {
        let returnedUrl = callbackUrl + "?sessionId=123&canceled=true"
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { _, _, completion in
            TestSession(completion: completion) { completion(URL(string: returnedUrl), nil); return true }
        }
        let result = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
        XCTAssertTrue(result.canceled)
        XCTAssertEqual(result.callbackUrl, returnedUrl)
        XCTAssertEqual(result.sessionId, "123")
        XCTAssertNil(result.redirectToken)
    }

    func testMissingNativeCallbackUrlThrows() async {
        let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
        client.makeAuthenticationSession = { _, _, completion in
            TestSession(completion: completion) { completion(nil, nil); return true }
        }
        do {
            _ = try await client.launchSession(launchUrl: launchUrl, callbackUrl: callbackUrl)
            XCTFail("Expected missing callback URL to throw")
        } catch {
            XCTAssertEqual((error as NSError).code, TrinsicErrorCode.unknownError.rawValue)
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
        XCTAssertNil(result.redirectToken)
        XCTAssertNil(result.callbackUrl)
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
        XCTAssertNil(result.sessionId)
        XCTAssertNil(result.redirectToken)
        XCTAssertNil(result.callbackUrl)
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

    func testInvalidCustomSchemesFailBeforeCreatingNativeSession() async {
        for scheme in ["example-app://", "example-app://callback/path", "example-app:", "1invalid",
                       "example_app", "a b", "example-app\n", "example-app\r\n", "éxample"] {
            let client = TrinsicUI(presentationContextProvider: TestPresentationContext())
            client.makeAuthenticationSession = { _, _, _ in
                XCTFail("Invalid scheme reached the native session factory: \(scheme.debugDescription)")
                throw TrinsicError.error(with: .unknownError)
            }
            do {
                _ = try await client.launchSession(launchUrl: launchUrl, callbackUrlScheme: scheme)
                XCTFail("Unexpectedly accepted \(scheme.debugDescription)")
            } catch {
                XCTAssertEqual((error as NSError).code, TrinsicErrorCode.unparsableCallbackUrl.rawValue, scheme.debugDescription)
            }
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
        XCTAssertEqual(result.callbackUrl, "example-app://session-complete?sessionId=123")
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
