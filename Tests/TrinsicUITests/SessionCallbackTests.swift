import AuthenticationServices
import XCTest
@testable import TrinsicUI

final class SessionCallbackTests: XCTestCase {
    private let callbackUrl = "https://example.com/session-complete"

    func testHttpsCallbackAcceptsResultParameters() throws {
        let callback = try SessionCallback(url: callbackUrl)
        XCTAssertTrue(callback.matchesResult(URL(string: callbackUrl + "?sessionId=123&redirectToken=token&success=true")!, sessionId: "123"))
        XCTAssertTrue(callback.matches(URL(string: "https://EXAMPLE.COM/session-complete?sessionId=123")!))
    }

    func testHttpsCallbackRejectsOtherDestinations() throws {
        let callback = try SessionCallback(url: callbackUrl)
        for url in [
            "http://example.com/session-complete",
            "example-app://session-complete",
            "https://example.com.evil.example/session-complete",
            "https://sub.example.com/session-complete",
            "https://example.com/session-complete/",
            "https://example.com/Session-complete",
            "https://example.com/session%2Dcomplete",
            "https://example.com/start-verification",
            "https://user@example.com/session-complete",
            "https://example.com:443/session-complete",
            "https://example.com/session-complete#fragment"
        ] {
            XCTAssertFalse(callback.matches(URL(string: url)!), url)
        }
    }

    func testResultMustBelongToLaunchedSession() throws {
        let callback = try SessionCallback(url: callbackUrl)
        for query in ["", "?sessionId=", "?sessionId=other", "?sessionId=123&sessionId=other", "?sessionId=123&sessionId=123"] {
            XCTAssertFalse(callback.matchesResult(URL(string: callbackUrl + query)!, sessionId: "123"), query)
        }
        XCTAssertFalse(callback.matchesResult(URL(string: callbackUrl + "?sessionId=123")!, sessionId: nil))
    }

    func testRejectsInvalidCallbackConfiguration() {
        for url in ["", "https", "/callback", "http://example.com/callback", "https:///callback",
                    "https://user:password@example.com/callback", "https://example.com:443/callback",
                    "https://example.com/callback?state=123", "https://example.com/callback#fragment",
                    "https://example.com/a b", "https://example.com/callback\n", "custom:opaque"] {
            XCTAssertThrowsError(try SessionCallback(url: url), url)
        }
    }

    func testCustomSchemeCompatibilityAndFullUrlMatching() throws {
        let scheme = try SessionCallback(customScheme: "Example-App")
        XCTAssertTrue(scheme.matches(URL(string: "example-app://session-complete?sessionId=123")!))
        XCTAssertTrue(scheme.matches(URL(string: "example-app:///another-path")!))
        XCTAssertFalse(scheme.matches(URL(string: callbackUrl)!))
        let full = try SessionCallback(url: "example-app://session-complete")
        XCTAssertTrue(full.matches(URL(string: "example-app://session-complete?sessionId=123")!))
        XCTAssertFalse(full.matches(URL(string: "example-app://launch?sessionId=123")!))
        XCTAssertTrue(try SessionCallback(url: "custom:/callback").matches(URL(string: "custom:/callback?sessionId=123")!))
    }

    func testSchemeOnlyApiRequiresCustomScheme() {
        for scheme in ["", "https", "HTTPS", "http", "example-app://", "1invalid", "a b"] {
            XCTAssertThrowsError(try SessionCallback(customScheme: scheme), scheme)
        }
    }

    @available(iOS 17.4, macOS 14.4, *)
    func testNativeHttpsCallbackMatchesExactHostAndPath() throws {
        let callback = try SessionCallback(url: callbackUrl).nativeCallback
        XCTAssertTrue(callback.matchesURL(URL(string: callbackUrl + "?sessionId=123")!))
        XCTAssertFalse(callback.matchesURL(URL(string: "https://other.example/session-complete")!))
        XCTAssertFalse(callback.matchesURL(URL(string: callbackUrl + "/other")!))
        XCTAssertFalse(callback.matchesURL(URL(string: "example-app://session-complete")!))
        XCTAssertTrue(try SessionCallback(customScheme: "example-app").nativeCallback.matchesURL(URL(string: "example-app://session-complete")!))
    }

    @available(iOS 17.4, macOS 14.4, *)
    func testNativeHttpsCallbackMatchesPercentEncodedPaths() throws {
        for path in ["/caf%C3%A9", "/a%20b", "/a%2Fb", "/a%2520b", "/session%2Dcomplete/"] {
            let address = "https://example.com" + path
            let callback = try SessionCallback(url: address)
            let result = try XCTUnwrap(URL(string: address + "?sessionId=123"))
            XCTAssertTrue(callback.nativeCallback.matchesURL(result), address)
            XCTAssertTrue(callback.matchesResult(result, sessionId: "123"), address)
        }
    }

    @available(iOS 17.4, macOS 14.4, *)
    func testResultValidationPreservesExactPathEncoding() throws {
        for (path, alternatePath) in [
            ("/session%2Dcomplete", "/session-complete"),
            ("/caf%C3%A9", "/caf%c3%a9"),
            ("/a%2Fb", "/a/b")
        ] {
            let callback = try SessionCallback(url: "https://example.com" + path)
            let result = try XCTUnwrap(URL(string: "https://example.com" + alternatePath + "?sessionId=123"))
            // Apple's decoded-path match must not relax the SDK's exact validation.
            XCTAssertTrue(callback.nativeCallback.matchesURL(result), alternatePath)
            XCTAssertFalse(callback.matchesResult(result, sessionId: "123"), alternatePath)
        }
    }

    @available(iOS 17.4, macOS 14.4, *)
    func testNativeHttpsCallbackMatchesInternationalizedHosts() throws {
        let hosts = ["xn--bcher-kva.example", "bücher.example", "XN--BCHER-KVA.EXAMPLE"]
        for host in hosts {
            let callback = try SessionCallback(url: "https://" + host + "/callback")
            for resultHost in hosts {
                let result = try XCTUnwrap(URL(string: "https://" + resultHost + "/callback?sessionId=123"))
                XCTAssertTrue(callback.nativeCallback.matchesURL(result), "\(host) -> \(resultHost)")
                XCTAssertTrue(callback.matchesResult(result, sessionId: "123"), "\(host) -> \(resultHost)")
            }
            let otherHost = try XCTUnwrap(URL(string: "https://sub.xn--bcher-kva.example/callback?sessionId=123"))
            XCTAssertFalse(callback.nativeCallback.matchesURL(otherHost))
            XCTAssertFalse(callback.matchesResult(otherHost, sessionId: "123"))
        }
    }

    func testRootCallbackPath() throws {
        let callback = try SessionCallback(url: "https://example.com")
        XCTAssertEqual(callback.path, "/")
        XCTAssertTrue(callback.matches(URL(string: "https://example.com/?sessionId=123")!))
    }
}
