import XCTest

final class ArabicJourneyTests: XCTestCase {
    @MainActor func testSourceConnectionDiagnostics() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["المزيد"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المزيد"].tap()
        let sources = app.buttons["more.sources"]
        for _ in 0..<6 where !sources.isHittable { app.swipeUp() }
        XCTAssertTrue(sources.isHittable)
        sources.tap()
        let check = app.buttons["sources.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        if !check.isHittable { app.swipeUp() }
        check.tap()
        for id in ["gateway", "gateway-data", "direct"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sources.result." + id).firstMatch.waitForExistence(timeout: 20))
        }
        XCTAssertTrue(app.staticTexts["المباريات عبر الخادم • متصل"].exists)
        capture("10-connection-diagnostics", app: app)
    }
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
        let saudiClub = app.buttons["search.team.espn:ksa.1:team:2276"]
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
        for _ in 0..<7 where !league.exists || !league.isHittable { app.swipeUp() }
        XCTAssertTrue(league.waitForExistence(timeout: 5), "Saudi league shortcut must exist in the reordered home catalogue")
        XCTAssertTrue(league.isHittable, "Saudi league shortcut must become hittable after scrolling the reordered home")
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
            if !featuredMatch.isHittable { app.swipeDown(); app.swipeDown() }
            if featuredMatch.isHittable {
                featuredMatch.tap()
                Thread.sleep(forTimeInterval: 12)
                capture("07-match-center", app: app)
                XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
            }
        }
    }

    @MainActor func testTransferReportsAndPlayerProfile() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["المزيد"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المزيد"].tap()
        let transfers = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "آخر أخبار سوق الانتقالات")).firstMatch
        XCTAssertTrue(transfers.waitForExistence(timeout: 10))
        transfers.tap()
        XCTAssertTrue(app.buttons["transfers.sources"].waitForExistence(timeout: 20))
        let article = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "transfers.article.")).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 25), "Transfer reports must be backed by source links")
        XCTAssertFalse(app.staticTexts["رسمي"].exists, "Headlines alone must not become verified deal labels")
        Thread.sleep(forTimeInterval: 3)
        capture("08-transfer-reports", app: app)
        app.tabBars.buttons["البحث"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("رونالدو\n")
        let player = app.buttons["search.player.tsdb:34146304"]
        XCTAssertTrue(player.waitForExistence(timeout: 30), "Player search must include the known provider record")
        if !player.isHittable { app.swipeUp() }
        player.tap()
        XCTAssertTrue(app.staticTexts["player.name"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 8)
        capture("09-player-source-coverage", app: app)
    }

    @MainActor func testMatchesHubInteractionPattern() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["المباريات"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المباريات"].tap()
        XCTAssertTrue(app.buttons["متابعاتي"].waitForExistence(timeout: 10))

        let updatedAt = app.staticTexts["page.lastUpdated"].firstMatch
        XCTAssertTrue(updatedAt.waitForExistence(timeout: 20))
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        XCTAssertTrue(updatedAt.label.contains(String(year)), "Refresh timestamp must use the Gregorian year")
        XCTAssertFalse(updatedAt.label.contains(where: { "٠١٢٣٤٥٦٧٨٩".contains($0) }), "Refresh timestamp must use Latin digits")

        let leagues = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matches.league."))
        XCTAssertTrue(leagues.firstMatch.waitForExistence(timeout: 20))
        var visibleLeague = leagues.allElementsBoundByIndex.first(where: { $0.isHittable })
        for _ in 0..<4 where visibleLeague == nil {
            app.swipeUp()
            visibleLeague = leagues.allElementsBoundByIndex.first(where: { $0.isHittable })
        }
        guard let league = visibleLeague else { return XCTFail("No hittable league header found") }

        let leagueTitle = league.staticTexts.firstMatch
        XCTAssertTrue(leagueTitle.exists, "Visible league header must expose its title")
        leagueTitle.tap()
        XCTAssertTrue(app.staticTexts["الترتيب والنتائج وأندية البطولة"].waitForExistence(timeout: 12), "Tapping the visible league title must open the league hub")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["المباريات"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المباريات"].tap()

        let matches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matches.match."))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 20))
        var visibleMatch = matches.allElementsBoundByIndex.first(where: { $0.isHittable })
        for _ in 0..<4 where visibleMatch == nil {
            app.swipeUp()
            visibleMatch = matches.allElementsBoundByIndex.first(where: { $0.isHittable })
        }
        guard let match = visibleMatch else { return XCTFail("No hittable match card found") }
        match.tap()
        XCTAssertTrue(app.buttons["match.follow"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["نظرة عامة"].exists || app.buttons["نظرة عامة"].exists)
        XCTAssertTrue(app.staticTexts["الإحصائيات"].exists || app.buttons["الإحصائيات"].exists)
        XCTAssertTrue(app.staticTexts["التشكيلة"].exists || app.buttons["التشكيلة"].exists)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
