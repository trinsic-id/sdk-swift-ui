import AuthenticationServices
import XCTest
@testable import TrinsicUI

@available(iOS 17.4, macOS 14.4, *)
final class SessionCallbackTests: XCTestCase {
    private let callbackUrl = "https://example.com/session-complete"

    func testNativeHttpsCallbackMatchesHostAndPath() throws {
        let callback = try SessionCallback(url: callbackUrl).nativeCallback
        XCTAssertTrue(callback.matchesURL(URL(string: callbackUrl + "?sessionId=123&redirectToken=token")!))
        XCTAssertTrue(callback.matchesURL(URL(string: "https://EXAMPLE.COM/session-complete")!))
        for url in [
            "example-app://session-complete",
            "https://example.com.evil.example/session-complete",
            "https://sub.example.com/session-complete",
            "https://example.com/start-verification"
        ] {
            XCTAssertFalse(callback.matchesURL(URL(string: url)!), url)
        }
    }

    func testCallbackConfigurationUsesOnlyNativeMatchingFields() throws {
        for address in [
            "https://user:password@example.com:443/session%2Dcomplete?state=123#fragment",
            "https://example.com/session-complete?",
            "https://example.com/session-complete#"
        ] {
            let callback = try SessionCallback(url: address)
            XCTAssertEqual(callback.host, "example.com")
            XCTAssertEqual(callback.path, "/session-complete")
            XCTAssertTrue(callback.nativeCallback.matchesURL(URL(string: callbackUrl)!), address)
        }
        let callback = try SessionCallback(url: "https://example.com/a b")
        XCTAssertTrue(callback.nativeCallback.matchesURL(URL(string: "https://example.com/a%20b")!))
    }

    func testRejectsConfigurationWithoutRequiredNativeFields() {
        for url in ["", "https", "/callback", "http://example.com/callback", "https:///callback", "https://[invalid"] {
            XCTAssertThrowsError(try SessionCallback(url: url), url)
        }
    }

    func testCustomSchemeCallbacksIgnoreHostAndPath() throws {
        let scheme = try SessionCallback(customScheme: "Example-App")
        XCTAssertTrue(scheme.nativeCallback.matchesURL(URL(string: "example-app://session-complete")!))
        XCTAssertFalse(scheme.nativeCallback.matchesURL(URL(string: callbackUrl)!))
        for address in ["example-app://configured/path?state=123#fragment", "example-app:/callback", "example-app:opaque"] {
            let callback = try SessionCallback(url: address)
            XCTAssertNil(callback.host)
            XCTAssertNil(callback.path)
            XCTAssertTrue(callback.nativeCallback.matchesURL(URL(string: "example-app://different-host/another-path")!))
            XCTAssertFalse(callback.nativeCallback.matchesURL(URL(string: "another-app://configured/path")!))
        }
    }

    func testSchemeOnlyApiRequiresCustomScheme() {
        for scheme in ["", "https", "HTTPS", "http"] {
            XCTAssertThrowsError(try SessionCallback(customScheme: scheme), scheme)
        }
    }

    func testValidCustomSchemeSyntaxIsAccepted() throws {
        for scheme in ["x", "Example-App", "com.example.app", "app+callback", "app123"] {
            let callback = try SessionCallback(customScheme: scheme)
            XCTAssertEqual(callback.scheme, scheme.lowercased())
            let url = try XCTUnwrap(URL(string: scheme.lowercased() + "://callback"))
            XCTAssertTrue(callback.nativeCallback.matchesURL(url), scheme)
        }
    }

    func testNativeHttpsCallbackMatchesPercentEncodedPaths() throws {
        for path in ["/caf%C3%A9", "/a%20b", "/a%2Fb", "/a%2520b", "/session%2Dcomplete/"] {
            let address = "https://example.com" + path
            let callback = try SessionCallback(url: address)
            let result = try XCTUnwrap(URL(string: address + "?sessionId=123"))
            XCTAssertTrue(callback.nativeCallback.matchesURL(result), address)
        }
    }

    func testNativeHttpsCallbackAcceptsEquivalentDecodedPaths() throws {
        for (path, alternatePath) in [
            ("/session%2Dcomplete", "/session-complete"),
            ("/caf%C3%A9", "/caf%c3%a9"),
            ("/a%2Fb", "/a/b")
        ] {
            let callback = try SessionCallback(url: "https://example.com" + path)
            let result = try XCTUnwrap(URL(string: "https://example.com" + alternatePath + "?sessionId=123"))
            XCTAssertTrue(callback.nativeCallback.matchesURL(result), alternatePath)
        }
    }

    func testNativeHttpsCallbackMatchesInternationalizedHosts() throws {
        let hosts = ["xn--bcher-kva.example", "bücher.example", "XN--BCHER-KVA.EXAMPLE"]
        for host in hosts {
            let callback = try SessionCallback(url: "https://" + host + "/callback")
            for resultHost in hosts {
                let result = try XCTUnwrap(URL(string: "https://" + resultHost + "/callback?sessionId=123"))
                XCTAssertTrue(callback.nativeCallback.matchesURL(result), "\(host) -> \(resultHost)")
            }
            let otherHost = try XCTUnwrap(URL(string: "https://sub.xn--bcher-kva.example/callback?sessionId=123"))
            XCTAssertFalse(callback.nativeCallback.matchesURL(otherHost))
        }
    }

    func testRootCallbackPath() throws {
        let callback = try SessionCallback(url: "https://example.com")
        XCTAssertEqual(callback.path, "/")
        XCTAssertTrue(callback.nativeCallback.matchesURL(URL(string: "https://example.com/?sessionId=123")!))
    }
}
