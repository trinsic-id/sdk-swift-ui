import PassKit

internal struct NativeWalletCapabilities {
    var version: OperatingSystemVersion
    static var current: Self { .init(version: ProcessInfo.processInfo.operatingSystemVersion) }

    func isAtLeast(_ major: Int, _ minor: Int = 0) -> Bool {
        version.majorVersion > major || (version.majorVersion == major && version.minorVersion >= minor)
    }

    func supports(_ type: NativeWalletDocumentType) -> Bool {
        switch type {
        case .driversLicense: return isAtLeast(16)
        case .nationalIDCard: return isAtLeast(18)
        case .photoID: return isAtLeast(26)
        }
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
public extension ParsedExchangeRequest {
    /// Legacy helper for callers that explicitly require a driver's-license descriptor.
    func toDriversLicenseDescriptor() throws -> PKIdentityDriversLicenseDescriptor {
        try ExchangeRequestTransformer.toPKIdentityDriversLicenseDescriptor(from: self)
    }

    func toDocumentDescriptors(diagnosticHandler: ((NativeWalletDiagnostic) -> Void)? = nil) throws
        -> [any PKIdentityDocumentDescriptor] {
        try ExchangeRequestTransformer.toPKIdentityDocumentDescriptors(from: self, diagnosticHandler: diagnosticHandler)
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
public class ExchangeRequestTransformer {
    public static func toPKIdentityDriversLicenseDescriptor(from request: ParsedExchangeRequest) throws
        -> PKIdentityDriversLicenseDescriptor {
        let descriptors = try toPKIdentityDocumentDescriptors(from: request)
        guard descriptors.count == 1, let descriptor = descriptors[0] as? PKIdentityDriversLicenseDescriptor else {
            throw ExchangeRequestTransformerError.unsupportedDocumentType("Expected a single DriversLicense request")
        }
        return descriptor
    }

    /// Returns complete document alternatives supported by this SDK and OS.
    /// A document with any unsupported attribute is skipped in its entirety.
    public static func toPKIdentityDocumentDescriptors(from request: ParsedExchangeRequest,
        diagnosticHandler: ((NativeWalletDiagnostic) -> Void)? = nil) throws -> [any PKIdentityDocumentDescriptor] {
        try descriptors(from: request, capabilities: .current, diagnosticHandler: diagnosticHandler)
    }

    internal static func descriptors(from request: ParsedExchangeRequest, capabilities: NativeWalletCapabilities,
        diagnosticHandler: ((NativeWalletDiagnostic) -> Void)?) throws -> [any PKIdentityDocumentDescriptor] {
        guard request.type == "mdlRequest", request.exchangeMechanism == "NativeApp" else {
            throw ExchangeRequestTransformerError.unsupportedExchangeType(
                request.type == "mdlRequest" ? request.exchangeMechanism : request.type)
        }
        guard request.platform == "apple-wallet" else {
            throw ExchangeRequestTransformerError.unsupportedPlatform(request.platform)
        }
        var result: [any PKIdentityDocumentDescriptor] = []
        for document in request.requestObject.documents {
            guard let type = NativeWalletDocumentType(rawValue: document.appleDocumentType) else {
                NativeWalletDiagnostics.emit(.unsupportedDocumentType, documentType: document.appleDocumentType, to: diagnosticHandler)
                continue
            }
            guard capabilities.supports(type), let descriptor = makeDescriptor(type) else {
                NativeWalletDiagnostics.emit(.documentUnavailableOnOS, documentType: type.rawValue, to: diagnosticHandler)
                continue
            }
            if let region = document.region {
                guard type == .nationalIDCard, region.utf8.count == 2,
                      region.utf8.allSatisfy({ (65...90).contains($0) }) else {
                    throw ExchangeRequestTransformerError.invalidRequestData
                }
                if #available(iOS 18.0, *), let national = descriptor as? PKIdentityNationalIDCardDescriptor {
                    national.region = Locale.Region(region)
                }
            }
            guard !document.requestedAttributes.isEmpty else {
                throw ExchangeRequestTransformerError.emptyRequestedAttributes(type.rawValue)
            }
            var seen = Set<String>()
            var unsupportedAttributes: [String] = []
            for attribute in document.requestedAttributes {
                guard seen.insert(attribute.attributeType).inserted, attribute.intentToStore >= -1 else {
                    throw ExchangeRequestTransformerError.invalidAttribute(attribute.attributeType)
                }
                do {
                    let element = try identityElement(attribute, documentType: type, capabilities: capabilities)
                    descriptor.addElements([element], intentToStore: .intent(attribute.intentToStore))
                } catch ExchangeRequestTransformerError.unsupportedAttribute(let name) {
                    // Continue validating the remaining attributes so unsupported
                    // fields cannot mask malformed known requirements.
                    unsupportedAttributes.append(name)
                }
            }
            guard !(seen.contains("Age") && seen.contains("AgeAtLeastX")) else {
                throw ExchangeRequestTransformerError.invalidAttribute("Age and AgeAtLeastX cannot be combined")
            }
            if !unsupportedAttributes.isEmpty {
                for name in unsupportedAttributes {
                    NativeWalletDiagnostics.emit(.unsupportedAttribute, documentType: type.rawValue,
                                                 attributeType: name, to: diagnosticHandler)
                }
                continue
            }
            result.append(descriptor)
        }
        guard !result.isEmpty else {
            NativeWalletDiagnostics.emit(.noSupportedDocuments, to: diagnosticHandler)
            throw ExchangeRequestTransformerError.noSupportedDocuments
        }
        return result
    }

    private static func makeDescriptor(_ type: NativeWalletDocumentType) -> (any PKIdentityDocumentDescriptor)? {
        switch type {
        case .driversLicense: return PKIdentityDriversLicenseDescriptor()
        case .nationalIDCard:
            if #available(iOS 18.0, *) { return PKIdentityNationalIDCardDescriptor() }
        case .photoID:
            if #available(iOS 26.0, *) { return PKIdentityPhotoIDDescriptor() }
        }
        return nil
    }

    private static func identityElement(_ attribute: ExchangeRequestAttribute, documentType: NativeWalletDocumentType,
                                        capabilities: NativeWalletCapabilities) throws -> PKIdentityElement {
        let name = attribute.attributeType
        guard let type = NativeWalletAttributeType(rawValue: name) else {
            throw ExchangeRequestTransformerError.unsupportedAttribute(name)
        }
        guard attribute.ageAtLeastXArgument == nil || type == .ageAtLeastX else {
            throw ExchangeRequestTransformerError.invalidAttribute(name)
        }
        guard type.supports(documentType) else {
            throw ExchangeRequestTransformerError.unsupportedAttribute(name)
        }
        switch type {
        case .givenName: return .givenName
        case .familyName: return .familyName
        case .portrait: return .portrait
        case .address: return .address
        case .dateOfBirth: return .dateOfBirth
        case .age: return .age
        case .ageAtLeastX:
            guard let age = attribute.ageAtLeastXArgument, (1...125).contains(age) else {
                throw ExchangeRequestTransformerError.invalidAttribute(name)
            }
            return .age(atLeast: age)
        case .issuingAuthority: return .issuingAuthority
        case .documentIssueDate: return .documentIssueDate
        case .documentExpirationDate: return .documentExpirationDate
        case .documentNumber: return .documentNumber
        case .drivingPrivileges: return .drivingPrivileges
        case .sex:
            if #available(iOS 17.2, *), capabilities.isAtLeast(17, 2) { return .sex }
        case .documentDHSComplianceStatus:
            if #available(iOS 17.2, *), capabilities.isAtLeast(17, 2) { return .documentDHSComplianceStatus }
        case .height, .weight, .eyeColor, .hairColor, .organDonorStatus, .veteranStatus:
            if #available(iOS 26.0, *), capabilities.isAtLeast(26) {
                switch type {
                case .height: return .height
                case .weight: return .weight
                case .eyeColor: return .eyeColor
                case .hairColor: return .hairColor
                case .organDonorStatus: return .organDonorStatus
                case .veteranStatus: return .veteranStatus
                default: break
                }
            }
        }
        throw ExchangeRequestTransformerError.unsupportedAttribute(name)
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable, message: "Not supported on macOS.")
@available(macCatalyst, unavailable, message: "Not supported on Mac Catalyst.")
public extension PKIdentityIntentToStore {
    static func intent(_ intentToStore: Int) -> PKIdentityIntentToStore {
        intentToStore > 0 ? .mayStore(days: intentToStore) : intentToStore < 0 ? .mayStore : .willNotStore
    }
}
