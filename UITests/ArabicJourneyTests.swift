import XCTest

final class ArabicJourneyTests: XCTestCase {
    @MainActor func testArabicNavigationAgainstLiveService() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 20), "The home page must launch")
        Thread.sleep(forTimeInterval: 18)
        capture("01-home-live", app: app)
        XCTAssertTrue(app.buttons["home.search"].isHittable)
        app.buttons["home.search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "Home search must open the search tab")
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("الاتحاد")
        Thread.sleep(forTimeInterval: 18)
        capture("02-arabic-search", app: app)
        app.tabBars.buttons["المباريات"].tap()
        Thread.sleep(forTimeInterval: 12)
        capture("03-matches-live", app: app)
        XCTAssertTrue(app.tabBars.buttons["المباريات"].isSelected)
        app.tabBars.buttons["الأخبار"].tap()
        Thread.sleep(forTimeInterval: 16)
        capture("04-news-live", app: app)
        XCTAssertTrue(app.tabBars.buttons["الأخبار"].isSelected)
        app.tabBars.buttons["الرئيسية"].tap()
        XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 10))
        let league = app.buttons["home.league.307"]
        for _ in 0..<6 { if league.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(league.isHittable, "Saudi league must be reachable from the dashboard")
        league.tap()
        Thread.sleep(forTimeInterval: 12)
        capture("05-league-live", app: app)
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists, "League details must retain a back route")
    }
    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
