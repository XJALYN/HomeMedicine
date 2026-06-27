import XCTest
@testable import HomeMedicine

final class BailianVisionServiceTests: XCTestCase {
    func testParseResultFromJSON() throws {
        let json = """
        {
          "name": "阿莫西林胶囊",
          "specification": "0.5g×24粒/盒",
          "manufacturer": "某某制药",
          "approvalNumber": "国药准字H12345678",
          "batchNumber": "20240101",
          "barcode": "6901339913419",
          "expiryDate": "2026-06-30",
          "usage": "口服，一次2粒",
          "symptoms": "细菌感染",
          "isOTC": false,
          "unit": "粒",
          "quantity": 24,
          "tags": ["antibiotic", "pain"]
        }
        """

        let result = try BailianVisionService.parseResult(from: json)
        XCTAssertEqual(result.name, "阿莫西林胶囊")
        XCTAssertEqual(result.specification, "0.5g×24粒/盒")
        XCTAssertEqual(result.manufacturer, "某某制药")
        XCTAssertEqual(result.barcode, "6901339913419")
        XCTAssertEqual(result.quantity, 24)
        XCTAssertFalse(result.isOTC)
        XCTAssertNotNil(result.expiryDate)
        XCTAssertEqual(result.tags, ["antibiotic", "pain"])
    }

    func testNormalizeTagsFiltersUnknown() {
        XCTAssertEqual(
            MedicineTags.normalize(["cold", "invalid", "FEVER", "cold"]),
            ["cold", "fever"]
        )
    }

    func testExtractJSONFromMarkdownBlock() {
        let text = """
        ```json
        {"name":"测试","specification":"10mg"}
        ```
        """
        let extracted = BailianVisionService.extractJSON(from: text)
        XCTAssertTrue(extracted.contains("\"name\":\"测试\""))
    }

    func testParseResultMissingNameThrows() {
        XCTAssertThrowsError(try BailianVisionService.parseResult(from: "{\"specification\":\"10mg\"}"))
    }

    func testParseResultAllowsMissingSpecification() throws {
        let result = try BailianVisionService.parseResult(from: "{\"name\":\"测试药品\"}")
        XCTAssertEqual(result.name, "测试药品")
        XCTAssertEqual(result.specification, "")
    }
}
