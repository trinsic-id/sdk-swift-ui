import PassKit

/// Presents native Apple Wallet identity requests. Submit the returned token to Trinsic unchanged.
@available(iOS 17.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
@MainActor
public class TrinsicMdl {
    private let controller: PKIdentityAuthorizationController
    private let diagnosticHandler: ((NativeWalletDiagnostic) -> Void)?
    internal var capabilities = NativeWalletCapabilities.current

    public init(controller: PKIdentityAuthorizationController? = nil,
                diagnosticHandler: ((NativeWalletDiagnostic) -> Void)? = nil) {
        self.controller = controller ?? PKIdentityAuthorizationController()
        self.diagnosticHandler = diagnosticHandler
    }

    /// Document types implemented by this SDK and available on the running iOS version.
    /// This does not establish app entitlements or the presence of a credential in Wallet.
    public static var supportedDocumentTypes: [String] {
        [NativeWalletDocumentType.driversLicense, .nationalIDCard, .photoID]
            .filter { NativeWalletCapabilities.current.supports($0) }.map(\.rawValue)
    }

    /// Accepts the challenge exactly as supplied by the backend, including document alternatives.
    /// Throws `documentRequestUnavailable` without presenting Wallet if preflight rejects every candidate.
    public func performMdlExchange(_ requestObjectBase64Url: String) async throws -> MdlExchangeResult {
        try Task.checkCancellation()
        let exchange = try NativeWalletRequestParser.parse(requestObjectBase64Url)
        let descriptors = try supportedDescriptors(exchange)
        let descriptor = try await selectDescriptor(descriptors)
        try Task.checkCancellation()
        let request = PKIdentityRequest()
        request.descriptor = descriptor
        request.merchantIdentifier = exchange.requestObject.merchantId
        request.nonce = try NativeWalletBase64.decode(exchange.requestObject.nonce)
        do {
            let document = try await controller.requestDocument(request)
            try Task.checkCancellation()
            return MdlExchangeResult(exchangeId: exchange.exchangeId, encryptedData: document.encryptedData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Preserve PassKit's error (including cancellation) for callers to inspect.
            throw TrinsicMdlError.documentRequestFailed(error)
        }
    }

    /// Checks whether Wallet can fulfill any supported document alternative in the challenge.
    public func canRequestDocument(_ requestObjectBase64Url: String) async throws -> Bool {
        try Task.checkCancellation()
        let exchange = try NativeWalletRequestParser.parse(requestObjectBase64Url)
        let descriptors = try supportedDescriptors(exchange)
        if #available(iOS 26.0, *), capabilities.isAtLeast(26), descriptors.count > 1 {
            let available = await controller.canRequestDocument(PKIdentityAnyOfDescriptor(descriptors: descriptors))
            try Task.checkCancellation()
            return available
        }
        for descriptor in descriptors {
            let available = await controller.canRequestDocument(descriptor)
            try Task.checkCancellation()
            if available { return true }
        }
        return false
    }

    /// Compatibility alias. This now checks every supported document type in the challenge.
    public func canRequestDriversLicense(_ requestObjectBase64Url: String) async throws -> Bool {
        try await canRequestDocument(requestObjectBase64Url)
    }

    /// Generic driver's-license/state-ID probe, independent of a specific challenge.
    public func userHasDriversLicense() async throws -> Bool {
        await controller.canRequestDocument(PKIdentityDriversLicenseDescriptor())
    }

    private func supportedDescriptors(_ exchange: ParsedExchangeRequest) throws -> [any PKIdentityDocumentDescriptor] {
        try ExchangeRequestTransformer.descriptors(from: exchange, capabilities: capabilities,
                                                   diagnosticHandler: diagnosticHandler)
    }

    private func selectDescriptor(_ descriptors: [any PKIdentityDocumentDescriptor]) async throws -> any PKIdentityDocumentDescriptor {
        // supportedDescriptors guarantees a nonempty array.
        var candidates = descriptors
        if #available(iOS 26.0, *), capabilities.isAtLeast(26), descriptors.count > 1 {
            candidates = [PKIdentityAnyOfDescriptor(descriptors: descriptors)]
        } else if descriptors.count > 1 {
            // Before iOS 26, try supported alternatives in backend preference order.
            NativeWalletDiagnostics.emit(.selectingSingleDocument, to: diagnosticHandler)
        }
        for descriptor in candidates {
            try Task.checkCancellation()
            let available = await controller.canRequestDocument(descriptor)
            try Task.checkCancellation()
            if available { return descriptor }
        }
        // A denied preflight can mean missing entitlements. Calling requestDocument
        // anyway can trigger an uncatchable CoreIDV assertion instead of an Error.
        throw TrinsicMdlError.documentRequestUnavailable
    }
}

public enum TrinsicMdlError: Error {
    case notSupported
    /// Legacy case retained for existing clients; no longer emitted for preflight rejection.
    @available(*, deprecated, renamed: "documentRequestUnavailable")
    case deviceDoesNotSupportMdl
    case unsupportedType
    case invalidRequest
    case documentRequestFailed(Error)
    case unknownError(Error)
    /// Wallet cannot fulfill this request, for any document type. Possible reasons include
    /// missing entitlements, an unsupported device, or no eligible ID; preflight doesn't distinguish them.
    case documentRequestUnavailable
}
