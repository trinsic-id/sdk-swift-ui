# Native Wallet contract fixtures

`native-wallet-contract.json` is also checked into Connect at
`Tests/UnitTests/Fixtures/AppleWallet/native-wallet-contract.json`. Keep the two
copies byte-for-byte identical when changing the contract.

Each case contains the backend request input, a fixed Base64URL challenge, and the
SDK's expected decoded values. Connect's `AppleWalletNativeContractTests` compares
its production request builder and native envelope serialization with the decoded
challenge. Swift's `NativeWalletContractTests` wraps the fixture's exchange request
in the required `v1` envelope; `NativeWalletDescriptorTests` does the same and checks
the resulting PassKit request on iOS 26+.
JSON escaping and property order are intentionally not part of the contract.

Cases cover standalone mDL, standalone PhotoID, and ordered PhotoID/mDL
alternatives, including binary nonce preservation, retention intent, and an age
threshold. All identifiers are synthetic. Japan's national ID is covered by the
SDK's descriptor tests; Connect does not yet generate that native request type.

Run `swift test` and `scripts/test-ios.sh`. In Connect, run
`AppleWalletNativeContractTests` after updating the matching fixture.

## Versioned native challenges

`native-challenge-versions.json` shares expected wire-level challenge tests.
Keep these copies byte-for-byte identical. Android carries the same selection
scenarios with Google Wallet payloads under `library/src/test/resources`.

`NativeChallengeVersionTests` exercises the production parser directly: it selects
the complete `v1` request, ignores unknown version payloads, and rejects missing or
malformed `v1` requests. The shared fixture's legacy scenarios are asserted to fail
with `unsupportedChallengeVersion`; its hypothetical v2/v10 SDK scenarios are
checked against this SDK's v1-only support. The shared fixture files remain
unchanged for use by the other SDKs.

Run `swift test --filter NativeChallenge` and `scripts/test-ios.sh`.
