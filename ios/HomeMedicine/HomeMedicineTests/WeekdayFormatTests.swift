import XCTest
@testable import HomeMedicine

final class WeekdayFormatTests: XCTestCase {
    func testChineseWeekdaySymbolsAreDistinct() {
        let locale = Locale(identifier: "zh-Hans")
        let labels = (0...6).map { WeekdayFormat.veryShortSymbol(for: $0, locale: locale) }
        XCTAssertEqual(Set(labels).count, 7, "Each weekday should have a unique label, got: \(labels)")
        XCTAssertEqual(labels[0], "日")
        XCTAssertEqual(labels[1], "一")
        XCTAssertEqual(labels[6], "六")
    }

    func testEnglishWeekdaySymbols() {
        let locale = Locale(identifier: "en")
        let monday = WeekdayFormat.veryShortSymbol(for: 1, locale: locale)
        let sunday = WeekdayFormat.veryShortSymbol(for: 0, locale: locale)
        XCTAssertEqual(monday, "M")
        XCTAssertEqual(sunday, "S")
    }

    func testDisplayOrderStartsWithMonday() {
        XCTAssertEqual(WeekdayFormat.displayOrder.first, 1)
        XCTAssertEqual(WeekdayFormat.displayOrder.last, 0)
    }
}
