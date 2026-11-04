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
    public func performMdlExchange(_ requestObjectBase64Url: String) async throws -> MdlExchangeResult {
        try Task.checkCancellation()
        let exchange = try NativeWalletRequestParser.parse(requestObjectBase64Url)
        let descriptors = try supportedDescriptors(exchange)
        let descriptor = await selectDescriptor(descriptors)
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

    private func selectDescriptor(_ descriptors: [any PKIdentityDocumentDescriptor]) async -> any PKIdentityDocumentDescriptor {
        // supportedDescriptors guarantees a nonempty array.
        if descriptors.count == 1 { return descriptors[0] }
        if #available(iOS 26.0, *), capabilities.isAtLeast(26) {
            return PKIdentityAnyOfDescriptor(descriptors: descriptors)
        }
        // Before iOS 26 there is no composite descriptor. Respect backend preference order
        // and choose the first available alternative without presenting multiple consent sheets.
        NativeWalletDiagnostics.emit(.selectingSingleDocument, to: diagnosticHandler)
        for descriptor in descriptors {
            if Task.isCancelled { break }
            if await controller.canRequestDocument(descriptor) { return descriptor }
        }
        // Availability is advisory; Wallet supplies the definitive error if none is available.
        return descriptors[0]
    }
}

public enum TrinsicMdlError: Error {
    case notSupported
    case deviceDoesNotSupportMdl
    case unsupportedType
    case invalidRequest
    case documentRequestFailed(Error)
    case unknownError(Error)
}
