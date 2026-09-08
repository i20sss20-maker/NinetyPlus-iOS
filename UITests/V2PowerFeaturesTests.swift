import XCTest

final class V2PowerFeaturesTests: XCTestCase {
    @MainActor
    func testPowerCenterSettingsAndSaudiHub() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["المزيد"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المزيد"].tap()

        let power = app.staticTexts["90+ 2.0"].firstMatch
        XCTAssertTrue(power.waitForExistence(timeout: 10), "2.0 power center must be reachable from More")
        power.tap()
        XCTAssertTrue(app.staticTexts["أدوات وتحليلات وتجربة شخصية"].waitForExistence(timeout: 10))

        let settings = app.staticTexts["إعدادات 2.0"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let digitPolicy = app.descendants(matching: .any)["settings.digits"]
        XCTAssertTrue(digitPolicy.waitForExistence(timeout: 8), "Arabic UI must expose the Latin digit policy through a stable accessibility marker")
        XCTAssertTrue(digitPolicy.label.contains("0–9"), "Digit policy must explicitly display Latin digits 0–9")
        XCTAssertTrue(app.switches["إخفاء النتائج — Spoiler Mode"].exists)
        XCTAssertTrue(app.switches["Low Data Mode"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        let saudi = app.staticTexts["كرة القدم السعودية"].firstMatch
        XCTAssertTrue(saudi.waitForExistence(timeout: 8))
        saudi.tap()
        XCTAssertTrue(app.staticTexts["كرة القدم السعودية في مكان واحد"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testLineupBuilderAndPlayerCompareAreRealRoutes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["المزيد"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المزيد"].tap()
        XCTAssertTrue(app.staticTexts["90+ 2.0"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["90+ 2.0"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["بناء التشكيلة"].firstMatch.waitForExistence(timeout: 8))
        app.staticTexts["بناء التشكيلة"].firstMatch.tap()
        XCTAssertTrue(app.buttons["مشاركة التشكيلة"].waitForExistence(timeout: 8))

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["مقارنة اللاعبين"].firstMatch.waitForExistence(timeout: 8))
        app.staticTexts["مقارنة اللاعبين"].firstMatch.tap()
        XCTAssertTrue(app.textFields["اسم اللاعب"].firstMatch.waitForExistence(timeout: 8))
    }
}
