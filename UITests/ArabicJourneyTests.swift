import XCTest

final class ArabicJourneyTests: XCTestCase {
    @MainActor func testArabicNavigationAgainstLiveService() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 15)
        capture("01-home-live", app: app)
        app.buttons["home.search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("الاتحاد\n")
        let saudiClub = app.buttons["search.team.2938"]
        XCTAssertTrue(saudiClub.waitForExistence(timeout: 35), "Arabic search must include the actual Saudi Al-Ittihad ID, not only its namesakes")
        XCTAssertTrue(saudiClub.isHittable, "The Saudi club must be visible without scrolling past unrelated namesakes")
        capture("02-arabic-search", app: app)
        saudiClub.tap()
        XCTAssertTrue(app.buttons["team.follow"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 18)
        capture("03-saudi-club", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["المباريات"].tap()
        Thread.sleep(forTimeInterval: 10)
        capture("04-matches-live", app: app)
        XCTAssertTrue(app.tabBars.buttons["المباريات"].isSelected)
        app.tabBars.buttons["الأخبار"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "news.featured").firstMatch.waitForExistence(timeout: 25), "A published article with an associated image must be available")
        Thread.sleep(forTimeInterval: 8)
        capture("05-news-live", app: app)
        app.tabBars.buttons["الرئيسية"].tap()
        XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 10))
        let league = app.buttons["home.league.307"]
        XCTAssertTrue(league.isHittable)
        league.tap()
        XCTAssertTrue(app.staticTexts["ترتيب الموسم الحالي"].waitForExistence(timeout: 25), "The current season must decode and pass its date validation")
        XCTAssertTrue(app.staticTexts["المصدر: ESPN"].exists)
        Thread.sleep(forTimeInterval: 6)
        capture("06-current-saudi-table", app: app)
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 10))
        let featuredMatch = app.buttons["home.featuredMatch"]
        if featuredMatch.exists {
            if !featuredMatch.isHittable { app.swipeUp() }
            featuredMatch.tap()
            Thread.sleep(forTimeInterval: 12)
            capture("07-match-center", app: app)
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
        }
    }
    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
