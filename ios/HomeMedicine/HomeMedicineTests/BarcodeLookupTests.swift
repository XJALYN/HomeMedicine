import XCTest
@testable import HomeMedicine

final class BarcodeLookupTests: XCTestCase {
    func testKnownBarcodeReturnsName() {
        let info = BarcodeLookupService.lookup(barcode: "6901339913419")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.name, "感冒灵颗粒")
        XCTAssertFalse(info?.specification.isEmpty ?? true)
    }

    func testFenbideBarcodeReturnsName() {
        let info = BarcodeLookupService.lookup(barcode: "6913991300322")
        XCTAssertNotNil(info)
        XCTAssertTrue(info?.name.contains("布洛芬") ?? false)
    }

    func testAmoxicillinBarcodeReturnsName() {
        let info = BarcodeLookupService.lookup(barcode: "6936292120055")
        XCTAssertNotNil(info)
        XCTAssertTrue(info?.name.contains("阿莫西林") ?? false)
    }

    func testSimulatorTestBarcode() {
        let info = BarcodeLookupService.lookup(barcode: "6901234567892")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.name, "阿莫西林胶囊")
    }

    func testLookupDoesNotIncludeExpiry() {
        let info = BarcodeLookupService.lookup(barcode: "6901339913419")
        XCTAssertNotNil(info)
        XCTAssertNotNil(info?.manufacturer)
        XCTAssertNotNil(info?.approvalNumber)
    }

    func testUnknownBarcodeReturnsNil() {
        XCTAssertNil(BarcodeLookupService.lookup(barcode: "0000000000000"))
    }

    func testUnknownBarcodeLookupResult() {
        let result = BarcodeLookupService.lookupResult(barcode: "0000000000000")
        guard case .notFound(let code) = result else {
            return XCTFail("Expected notFound")
        }
        XCTAssertEqual(code, "0000000000000")
    }

    func testNormalizeStripsSpacesAndHyphens() {
        XCTAssertEqual(
            BarcodeLookupService.normalizeBarcode("6901-3399 1341 9"),
            "6901339913419"
        )
    }

    func testNormalizeUPCAToEAN13() {
        XCTAssertEqual(
            BarcodeLookupService.normalizeBarcode("036000291452"),
            "0036000291452"
        )
    }

    func testLookupKeysIncludeUPCVariantForLeadingZeroEAN() {
        let keys = BarcodeLookupService.lookupKeys(for: "0036000291452")
        XCTAssertTrue(keys.contains("0036000291452"))
        XCTAssertTrue(keys.contains("036000291452"))
    }

    func testSubmitUnknownBarcodeStoresPending() {
        let key = "pendingBarcodeSubmissions"
        let defaults = UserDefaults.standard
        let previous = defaults.stringArray(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        defaults.set([], forKey: key)
        BarcodeLookupService.submitUnknownBarcode("6900000000001")
        XCTAssertTrue(BarcodeLookupService.pendingBarcodes().contains("6900000000001"))
    }
}
