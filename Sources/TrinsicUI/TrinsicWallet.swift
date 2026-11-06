import PassKit

/// Presents native Apple Wallet identity requests. Submit the returned token to Trinsic unchanged.
@available(iOS 17.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
@MainActor
public class TrinsicWallet {
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
    public func performExchange(_ requestObjectBase64Url: String) async throws -> WalletExchangeResult {
        try Task.checkCancellation()
        let exchange = try NativeWalletRequestParser.parse(requestObjectBase64Url)
        let descriptors = try supportedDescriptors(exchange)
        // Recheck even if the caller already used canRequestDocument: availability
        // may have changed, and no denied descriptor may reach presentation.
        guard let descriptor = try await availableDescriptor(descriptors) else {
            throw TrinsicWalletError.documentRequestUnavailable
        }
        try Task.checkCancellation()
        NativeWalletDiagnostics.emit(.documentSelected, documentType: documentType(descriptor), to: diagnosticHandler)
        try Task.checkCancellation()
        let request = PKIdentityRequest()
        request.descriptor = descriptor
        request.merchantIdentifier = exchange.requestObject.merchantId
        request.nonce = try NativeWalletBase64.decode(exchange.requestObject.nonce)
        do {
            let document = try await controller.requestDocument(request)
            try Task.checkCancellation()
            return WalletExchangeResult(exchangeId: exchange.exchangeId, encryptedData: document.encryptedData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Preserve PassKit's error (including cancellation) for callers to inspect.
            throw TrinsicWalletError.documentRequestFailed(error)
        }
    }

    /// Compatibility alias for exchanging any supported Wallet document type.
    @available(*, deprecated, renamed: "performExchange(_:)")
    public func performMdlExchange(_ requestObjectBase64Url: String) async throws -> WalletExchangeResult {
        try await performExchange(requestObjectBase64Url)
    }

    /// Checks whether Wallet can fulfill any supported document alternative in the challenge.
    public func canRequestDocument(_ requestObjectBase64Url: String) async throws -> Bool {
        try Task.checkCancellation()
        let exchange = try NativeWalletRequestParser.parse(requestObjectBase64Url)
        let descriptors = try supportedDescriptors(exchange)
        return try await availableDescriptor(descriptors) != nil
    }

    /// Compatibility alias. This now checks every supported document type in the challenge.
    @available(*, deprecated, renamed: "canRequestDocument(_:)")
    public func canRequestDriversLicense(_ requestObjectBase64Url: String) async throws -> Bool {
        try await canRequestDocument(requestObjectBase64Url)
    }

    /// Generic driver's-license/state-ID probe, independent of a specific challenge.
    public func userHasDriversLicense() async throws -> Bool {
        await controller.canRequestDocument(PKIdentityDriversLicenseDescriptor())
    }

    private func supportedDescriptors(_ exchange: ParsedExchangeRequest) throws -> [any PKIdentityDocumentDescriptor] {
        if diagnosticHandler != nil {
            NativeWalletDiagnostics.emit(.requestParsed,
                request: try NativeWalletRequestSummary(exchange: exchange), to: diagnosticHandler)
        }
        return try ExchangeRequestTransformer.descriptors(from: exchange, capabilities: capabilities,
                                                          diagnosticHandler: diagnosticHandler)
    }

    private func availableDescriptor(_ descriptors: [any PKIdentityDocumentDescriptor]) async throws -> (any PKIdentityDocumentDescriptor)? {
        // supportedDescriptors guarantees a nonempty array.
        if #available(iOS 26.0, *), capabilities.isAtLeast(26), descriptors.count > 1 {
            let composite = PKIdentityAnyOfDescriptor(descriptors: descriptors)
            if try await isAvailable(composite) { return composite }
            // Apple may reject a composite containing an unentitled type even
            // though another complete alternative is permitted. Probe the exact
            // originals; never remove fields or manufacture a different request.
        }
        if descriptors.count > 1 {
            NativeWalletDiagnostics.emit(.selectingSingleDocument, to: diagnosticHandler)
        }
        for descriptor in descriptors {
            if try await isAvailable(descriptor) { return descriptor }
        }
        // A denied preflight can mean missing entitlements. Calling requestDocument
        // anyway can trigger an uncatchable CoreIDV assertion instead of an Error.
        return nil
    }

    private func isAvailable(_ descriptor: any PKIdentityDocumentDescriptor) async throws -> Bool {
        try Task.checkCancellation()
        let available = await controller.canRequestDocument(descriptor)
        try Task.checkCancellation()
        NativeWalletDiagnostics.emit(.availabilityChecked, documentType: documentType(descriptor),
                                     isAvailable: available, to: diagnosticHandler)
        try Task.checkCancellation()
        return available
    }

    private func documentType(_ descriptor: any PKIdentityDocumentDescriptor) -> String {
        if descriptor is PKIdentityDriversLicenseDescriptor { return "DriversLicense" }
        if #available(iOS 18.0, *), descriptor is PKIdentityNationalIDCardDescriptor { return "NationalIDCard" }
        if #available(iOS 26.0, *) {
            if descriptor is PKIdentityPhotoIDDescriptor { return "PhotoID" }
            if descriptor is PKIdentityAnyOfDescriptor { return "AnyOf" }
        }
        return "Unknown"
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
@available(*, deprecated, renamed: "TrinsicWallet")
public typealias TrinsicMdl = TrinsicWallet

public enum TrinsicWalletError: Error {
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

@available(*, deprecated, renamed: "TrinsicWalletError")
public typealias TrinsicMdlError = TrinsicWalletError
