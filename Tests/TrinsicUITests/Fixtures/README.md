# Native Wallet contract fixtures

`native-wallet-contract.json` is also checked into Connect at
`Tests/UnitTests/Fixtures/AppleWallet/native-wallet-contract.json`. Keep the two
copies byte-for-byte identical when changing the contract.

Each case contains the backend request input, a fixed Base64URL challenge, and the
SDK's expected decoded values. Connect's `AppleWalletNativeContractTests` compares
its production request builder and native envelope serialization with the decoded
challenge. Swift's `NativeWalletContractTests` consumes the challenge directly;
`NativeWalletDescriptorTests` checks the resulting PassKit request on iOS 26+.
JSON escaping and property order are intentionally not part of the contract.

Cases cover standalone mDL, standalone PhotoID, and ordered PhotoID/mDL
alternatives, including binary nonce preservation, retention intent, and an age
threshold. All identifiers are synthetic. Japan's national ID is covered by the
SDK's descriptor tests; Connect does not yet generate that native request type.

Run `swift test` and `scripts/test-ios.sh`. In Connect, run
`AppleWalletNativeContractTests` after updating the matching fixture.
