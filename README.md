# Trinsic Swift UI Library

[![Swift UI Version](https://img.shields.io/cocoapods/v/TrinsicUI.svg)](<[https://cocoapods.org/pods/TrinsicUI](https://cocoapods.org/pods/TrinsicUI)>) [![Swift Build Status](https://github.com/trinsic-id/sdk/actions/workflows/ui-swift-release.yml/badge.svg)](https://github.com/trinsic-id/sdk/actions?query=branch%main)

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

This library provides **only minimal** support for [Direct Provider Sessions](https://docs.trinsic.id/docs/direct-provider-session).

Specifically, it can be used only to execute Sessions which return a `launchMethod` of `LaunchBrowser` and a `collectionMethod` of `CaptureRedirect`.

All other interaction methods are not supported by this library and will require additional effort to implement; please contact Trinsic for guidance.

## Installation

### Swift package manager

Add the Trinsic repository `https://github.com/trinsic-id/sdk-swift-ui` as a dependency.

### CocoaPods

Add a reference to the `TrinsicUI` pod to your `Podfile` with the latest version (see the shield at the top of the readme) and run `pod install`

```
pod 'TrinsicUI', '~> [latest version]'
```

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

```swift
let trinsicUI = TrinsicUI()
let result = try await trinsicUI.launchSession(launchUrl: "[REPLACE_ME]", callbackUrlScheme: "[REPLACE_ME]")

if let redirectToken = result.redirectToken {
    // Send this token to your backend; it will play a core role in future
    // high-assurance / same-device guarantees.
    sendRedirectTokenToBackend(redirectToken)
}
```

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

The `callbackUrl` overload matches the returned URL's scheme and host case-insensitively and its path exactly, including case and percent-encoding. For example, `/session-complete`, `/session-complete/` and `/Session-complete` are different paths. An empty HTTPS path is treated as `/`.

Query parameters are handled separately from the callback address. Supply an absolute HTTPS or custom-scheme URL without credentials, an explicit port, query or fragment; caller-supplied query parameters such as `?state=123` are not supported by this overload. Trinsic appends result parameters, so a return URL such as `https://example.com/session-complete?sessionId=123&redirectToken=...` matches the callback above. The SDK also requires exactly one `sessionId` parameter matching the launched Session before parsing the result.

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
