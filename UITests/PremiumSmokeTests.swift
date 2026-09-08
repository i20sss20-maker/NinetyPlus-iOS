import XCTest

final class PremiumSmokeTests: XCTestCase {
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func tap(_ app: XCUIApplication, _ id: String) {
        let target = element(app, id)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "Missing \(id)")
        for _ in 0..<7 {
            if target.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable, "Unreachable \(id)")
        target.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPulseBriefAndReadingRoom() {
        let app = XCUIApplication(); app.launch()
        tap(app, "home.pulse")
        XCTAssertTrue(app.staticTexts["90+ Pulse"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["وش فاتني؟"].firstMatch.tap()
        XCTAssertTrue(element(app, "pulse.markRead").waitForExistence(timeout: 10))
        capture(app, "Pulse-Brief")
        tap(app, "pulse.reading")
        XCTAssertTrue(app.staticTexts["غرفة الأخبار"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["المحفوظة"].firstMatch.tap()
        capture(app, "Reading-room-saved")
    }
    func testLineupPersistsAcrossRelaunch() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["المزيد"].tap()
        tap(app, "more.power"); tap(app, "power.lineup")
        let field = app.textFields["lineup.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(" QA90")
        let expected = field.value as? String
        XCTAssertTrue(expected?.contains("QA90") == true)
        app.terminate(); app.launch()
        app.tabBars.buttons["المزيد"].tap()
        tap(app, "more.power"); tap(app, "power.lineup")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, expected)
        XCTAssertTrue(element(app, "lineup.captain").exists)
        capture(app, "Saved-lineup-restored")
    }
}
