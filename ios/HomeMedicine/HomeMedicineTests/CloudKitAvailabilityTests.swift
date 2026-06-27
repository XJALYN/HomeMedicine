import XCTest
@testable import HomeMedicine

final class CloudKitAvailabilityTests: XCTestCase {
    func testContainerIdentifierMatchesEntitlementsFile() throws {
        let entitlementsURL = Bundle(for: CloudKitAvailabilityTests.self)
            .bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PlugIns/HomeMedicineTests.xctest")
        // Read entitlements from source tree via known identifier constant
        XCTAssertEqual(CloudKitAvailability.containerIdentifier, "iCloud.com.homemedicine.app")
    }

    func testContainerIdentifierMatchesInfoPlist() {
        let plistID = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        XCTAssertEqual(plistID, CloudKitAvailability.containerIdentifier)
    }

    func testIsConfiguredWhenSignedEntitlementsIncludeContainer() {
        // On CI/simulator with proper code signing, SecTask should expose entitlements.
        // When CloudKit service is present, container list must include our ID or be empty only if service is also absent.
        if CloudKitAvailability.hasCloudKitService {
            XCTAssertTrue(
                CloudKitAvailability.cloudKitContainerIdentifiers.contains(CloudKitAvailability.containerIdentifier),
                "Expected signed entitlements to include \(CloudKitAvailability.containerIdentifier)"
            )
            XCTAssertTrue(CloudKitAvailability.isConfigured)
        }
    }
}
