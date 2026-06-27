import XCTest

final class HomeMedicineUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    func testTabBarExists() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testNavigateToAddTab() throws {
        let addTab = app.tabBars.buttons.element(boundBy: 1)
        if addTab.waitForExistence(timeout: 3) {
            addTab.tap()
        }
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
    }

    func testNavigateToProfileTab() throws {
        let profileTab = app.tabBars.buttons.element(boundBy: 3)
        if profileTab.waitForExistence(timeout: 3) {
            profileTab.tap()
        }
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 3) || app.navigationBars.firstMatch.exists)
    }
}
