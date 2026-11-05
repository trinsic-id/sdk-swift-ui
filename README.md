# Trinsic Swift UI Library

[![Swift Build Status](https://github.com/trinsic-id/sdk/actions/workflows/ui-swift-release.yml/badge.svg)](https://github.com/trinsic-id/sdk/actions?query=branch%main)

The Trinsic Swift UI Library provides ways to launch verification sessions directly in your Swift and Objective-C projects.

This library must be paired with an [api library](https://github.com/trinsic-id/sdk#api-libraries) as part of a full integration.

You can find a full example using this library in the [samples](https://github.com/trinsic-id/sdk/tree/main/ui-swift/samples) folder.

## Documentation

See the [Trinsic docs](https://docs.trinsic.id/docs/) for more detailed information on how to start integrating with our identity acceptance network.

## Supported Use Cases

### Widget and Hosted Provider Sessions

This library supports launching both [Widget](https://docs.trinsic.id/docs/widget-session) and [Hosted Provider](https://docs.trinsic.id/docs/hosted-provider-session) Sessions.

You _must_ specify a `redirectUrl` when creating either kind of Session, and that `redirectUrl` must be either an HTTPS callback on a domain associated with your app or a registered custom-scheme URL (see below).

### Direct Provider Sessions

For [Direct Provider Sessions](https://docs.trinsic.id/docs/direct-provider-session), the browser API handles `LaunchBrowser` with `CaptureRedirect`.

For native Apple Wallet, build with Xcode 26+. `TrinsicMdl` supports driver's licenses/state IDs on iOS 17+, national IDs on iOS 18+, and Photo ID on iOS 26+, subject to Wallet availability and app entitlements. Pass the backend challenge unchanged to `canRequestDocument` and `performMdlExchange`; submit the returned `exchangeId` and `token` unchanged to your backend.

A false availability result must stop presentation: Apple may terminate the app for an unentitled request. `performMdlExchange` also checks availability internally and throws `TrinsicMdlError.documentRequestUnavailable` if no candidate passes, including when called without a prior availability check. This applies to every document type and does not imply a hardware limitation: missing entitlements or an unavailable credential can also cause rejection. A true result does not validate merchant configuration or guarantee verification success.

The legacy `deviceDoesNotSupportMdl` case remains deprecated for existing references; this path no longer throws it. Update exhaustive switches over `TrinsicMdlError` to handle `documentRequestUnavailable` when upgrading.

Native challenges must contain a `v1` property with a complete exchange request. The SDK ignores other versions and unversioned sibling fields. A challenge without `v1`, including a legacy unversioned challenge, throws `ExchangeRequestTransformerError.unsupportedChallengeVersion`. A malformed `v1` fails validation.

The backend may send a single document or `documentRequests` alternatives, of which any one may satisfy the request. Other extra JSON properties are ignored. Unknown or OS-unavailable document types, and whole alternatives with unsupported attributes, are skipped with diagnostics; malformed known fields still fail. If no complete supported alternative remains, the exchange fails before opening Wallet. Use `diagnosticHandler` for warnings and errors.

Your application/backend owns Session creation, challenge refresh, response submission, and result collection.

## Installation

### Swift package manager

Add the Trinsic repository `https://github.com/trinsic-id/sdk-swift-ui` as a dependency.

## Setup

### Choose a Custom Scheme

This library makes use of `ASWebAuthenticationSession` on iOS and macOS.

For a custom-scheme callback, register the scheme against your app on both iOS and macOS. The existing `callbackUrlScheme` API remains supported. Pass only the scheme to that API, never `https` or a complete URL.

This custom scheme **should be globally unique to your organization and application**.

An example of a good custom scheme might be `acme-corp-shopping-app-trinsic`.

#### Add the scheme to your app's URLs

Select your app's target and on the info tab in XCode add the scheme you selected.

## Usage

Import TrinsicUI into your view:

```swift
import TrinsicUI
```

Create an instance of TrinsicUI and launch a session.
You can retrieve the launch url from a trusted backend that can reach out to the Trinsic servers. [See our API libraries.](https://github.com/trinsic-id/sdk#api-libraries)

The `launchUrl` parameter must contain exactly one nonempty `sessionId` query parameter (for example, `https://verify.trinsic.id/?sessionId=123`). If you wrap the SDK or supply a wrapper/redirect URL, preserve `sessionId` as a top-level query parameter on the URL passed to `launchSession`, not just inside an embedded URL. The SDK reads this value to validate the returned session ID, and passes the launch URL to the native browser session unchanged without adding `launchMode`.

```swift
let trinsicUI = TrinsicUI()
let result = try await trinsicUI.launchSession(launchUrl: "[REPLACE_ME]", callbackUrlScheme: "[REPLACE_ME]")

if let redirectToken = result.redirectToken {
    // Send this token to your backend; it will play a core role in future
    // high-assurance / same-device guarantees.
    sendRedirectTokenToBackend(redirectToken)
}
```

`LaunchSessionResult` contains:

- `sessionId: String?`: the decoded ID from the returned URL, validated against the launch URL's ID. It is `nil` on local cancellation; other results require exactly one matching ID.
- `redirectToken: String?`: the decoded token from the returned URL. Missing or empty values are `nil`; if the parameter is repeated, the first value is used.
- `callbackUrl: String?`: the full URL returned by the native authentication session, including its query and fragment. This is `nil` on local cancellation.
- `canceled: Bool`: `true` on local cancellation or when the returned URL contains `canceled=true`.

`success` and `resultsAccessKey` are no longer result properties. Use your backend's Trinsic API response for Session status and its stored results access key.

## HTTPS callbacks (iOS 17.4+ / macOS 14.4+)

The backend's `redirectUrl` tells Trinsic where to redirect the browser when verification finishes. The SDK also needs that address to tell Apple's `ASWebAuthenticationSession` which redirect should finish the browser session and return a result to your app. For HTTPS, Apple's [`ASWebAuthenticationSession.Callback.https(host:path:)`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)) API requires the expected host and path before the browser opens. Setting `redirectUrl` on the backend does not configure this native callback handler, and the SDK does not fetch the Session's redirect configuration from the backend.

Pass the complete callback address to the `callbackUrl` overload. Set the same address as `redirectUrl` when your backend creates the Session, and register it in the Trinsic redirect allowlist for the relevant environment. The SDK does not change the Session's redirect URL.

```swift
let result = try await trinsicUI.launchSession(
    launchUrl: launchUrl,
    callbackUrl: "https://example.com/session-complete"
)
if !result.canceled {
    // Send result.sessionId and result.redirectToken to your backend.
}
```

Callback matching is handled by Apple's `ASWebAuthenticationSession`. HTTPS callbacks use the host and decoded path, so equivalent percent-encodings match (for example, `/session%2Dcomplete` and `/session-complete`). An empty HTTPS path is treated as `/`. Custom-scheme callbacks match only the scheme, even when a complete callback URL is supplied; their host and path do not restrict matching.

Credentials, an explicit port, query parameters, and a fragment in the configured callback URL are not passed to Apple's matcher. The SDK does not reject these fields or perform additional callback address comparisons. It separately requires exactly one `sessionId` in the returned URL whose decoded value matches the launch URL's ID. Missing, empty, duplicate or mismatched returned IDs throw an error. Local cancellation does not require a returned URL or session ID.

For HTTPS, configure **Associated Domains** on your app target and provisioning profiles:

```text
webcredentials:example.com
```

Apple's authentication-session HTTPS callback requires the **webcredentials** service. An `applinks` entry by itself is insufficient. Serve this JSON at `https://example.com/.well-known/apple-app-site-association`, without a redirect, using your actual domain and application identifier:

```json
{
  "webcredentials": {
    "apps": ["YOUR_APP_ID_PREFIX.YOUR_BUNDLE_ID"]
  }
}
```

If the domain also opens your app from links outside an active SDK session, keep `applinks:example.com` in your entitlements and the corresponding `applinks` section in the same association file. Handle those incoming links in your app as usual; the SDK captures verification callbacks through its authentication session and does not require an `onOpenURL` forwarding hook.

HTTPS callbacks fail with `unsupportedHttpsLinking` on iOS versions before 17.4. For those devices, create the Session with a registered custom-scheme `redirectUrl` and use either the existing scheme-only API or `callbackUrl: "your-scheme://callback"`. There is no automatic downgrade, because the backend must use the same redirect address. `cancel()` applies to both overloads.

Keep a dedicated callback path, such as `/session-complete`, separate from links that launch a new verification, such as `/start-verification`.

### Validation

Run `swift test` for callback matching and native callback selection tests. Before releasing an app, install a signed build after publishing the association file and complete a real Session on iOS 17.4+; also verify cancellation and custom-scheme fallback. Unit tests do not verify the live domain association or backend allowlist.

## SDK Versioning

Our SDKs follow the [Semantic Versioning](https://semver.org) ("SemVer") scheme.

For example, the version number `1.13.0` has a major version of `1`, a minor version of `13`, and a patch version of `0`.

Breaking changes are only introduced alongside a new major version.

## Support

Any issues, inquiries, and feature requests can be sent to [support@trinsic.id](mailto:support@trinsic.id), or feel free to open a GitHub issue [here](https://github.com/trinsic-id/sdk/issues).

## More Information

- [API Reference](https://docs.trinsic.id/reference)
- [Developer Guide](https://docs.trinsic.id/docs/developer-tools)
- [Our Blog](https://trinsic.id/blog/)
- [Schedule a demo](https://trinsic.id/contact/)
