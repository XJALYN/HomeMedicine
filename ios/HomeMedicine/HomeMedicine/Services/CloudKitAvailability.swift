import CloudKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.homemedicine.app", category: "CloudKitAvailability")

enum CloudKitAvailability {
    /// Must match `HomeMedicine.entitlements` and the CloudKit container in Xcode.
    static let containerIdentifier = "iCloud.com.homemedicine.app"

    static var isConfigured: Bool {
        guard hasCloudKitService else {
            logger.info("CloudKit disabled: signed app lacks com.apple.developer.icloud-services.")
            return false
        }
        guard cloudKitContainerIdentifiers.contains(containerIdentifier) else {
            logger.error("CloudKit container \(containerIdentifier, privacy: .public) not found in signed entitlements.")
            return false
        }
        return true
    }

    static var hasCloudKitService: Bool {
        if let services = provisioningEntitlementValue(for: "com.apple.developer.icloud-services") as? [String] {
            return services.contains("CloudKit")
        }
        return infoPlistContainerIdentifier != nil
    }

    static var cloudKitContainerIdentifiers: [String] {
        if let identifiers = provisioningEntitlementValue(for: "com.apple.developer.icloud-container-identifiers") as? [String],
           !identifiers.isEmpty {
            return identifiers
        }
        if let plistID = infoPlistContainerIdentifier {
            return [plistID]
        }
        return []
    }

    /// Never call `CKContainer.default()`. Only construct after `isConfigured` is true.
    static var container: CKContainer? {
        guard isConfigured else { return nil }
        return CKContainer(identifier: containerIdentifier)
    }

    private static var infoPlistContainerIdentifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func provisioningEntitlementValue(for key: String) -> Any? {
        guard let entitlements = embeddedProvisioningPlist?["Entitlements"] as? [String: Any] else {
            return nil
        }
        return entitlements[key]
    }

    private static var embeddedProvisioningPlist: [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return extractPlist(from: data)
    }

    private static func extractPlist(from data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else {
            return nil
        }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
    }
}
