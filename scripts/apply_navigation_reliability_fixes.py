from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")


def unwrap_navigation_stack(text, body_start, body_end):
    start = text.index(body_start)
    end = text.index(body_end, start)
    block = text[start:end]
    nav = block.index("NavigationStack {")
    brace = block.index("{", nav)
    depth = 0
    close = None
    for i, ch in enumerate(block[brace:], start=brace):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                close = i
                break
    if close is None:
        raise RuntimeError("NavigationStack closing brace not found")
    inner = block[brace + 1:close]
    lines = inner.splitlines()
    inner = "\n".join(line[4:] if line.startswith("    ") else line for line in lines).strip("\n")
    return text[:start], inner, text[end:]


# Search is both a tab root and a pushed destination. Avoid nesting NavigationStack
# when it is opened from More/Favorites.
path = "Sources/Views/V2Discovery.swift"
s = read(path)
if "let embedded: Bool" not in s:
    s = s.replace(
        "struct V2DiscoverView: View {\n",
        "struct V2DiscoverView: View {\n    let embedded: Bool\n    init(embedded: Bool = false) { self.embedded = embedded }\n",
        1,
    )
    prefix, inner, suffix = unwrap_navigation_stack(
        s,
        "    var body: some View {",
        "    @MainActor private func dismissKeyboard()",
    )
    body = (
        "    var body: some View {\n"
        "        Group {\n"
        "            if embedded { content }\n"
        "            else { NavigationStack { content } }\n"
        "        }\n"
        "    }\n\n"
        "    private var content: some View {\n"
        + inner
        + "\n    }\n"
    )
    s = prefix + body + suffix
write(path, s)

# Transfers is only pushed from More, so its own NavigationStack was a nested stack.
path = "Sources/Views/EnhancedTransfersView.swift"
s = read(path)
if "NavigationStack {" in s[s.index("    var body: some View {"):s.index("    private var transfermarktPanel")]:
    prefix, inner, suffix = unwrap_navigation_stack(
        s,
        "    var body: some View {",
        "    private var transfermarktPanel",
    )
    s = prefix + "    var body: some View {\n" + inner + "\n    }\n\n" + suffix
write(path, s)

# Make all pushed search routes use the parent's navigation stack and give More cards
# stable identifiers for an exhaustive smoke test.
path = "Sources/Views/V2Personalization.swift"
s = read(path)
s = s.replace("NavigationLink { V2DiscoverView() } label: {", "NavigationLink { V2DiscoverView(embedded: true) } label: {")
s = s.replace(
    'NavigationLink { V2FavoritesView() } label: { card("المتابعة", "أنديتك ولاعبوك المفضلون", "star.fill") }',
    'NavigationLink { V2FavoritesView() } label: { card("المتابعة", "أنديتك ولاعبوك المفضلون", "star.fill") }.accessibilityIdentifier("more.favorites")',
)
s = s.replace(
    'NavigationLink { V2LeaguesListView() } label: { card("البطولات", "الترتيب والمباريات والهدافون", "trophy.fill") }',
    'NavigationLink { V2LeaguesListView() } label: { card("البطولات", "الترتيب والمباريات والهدافون", "trophy.fill") }.accessibilityIdentifier("more.leagues")',
)
s = s.replace(
    'NavigationLink { EnhancedTransfersView() } label: { card("الانتقالات", "آخر أخبار سوق الانتقالات", "arrow.left.arrow.right") }',
    'NavigationLink { EnhancedTransfersView() } label: { card("الانتقالات", "آخر أخبار سوق الانتقالات", "arrow.left.arrow.right") }.accessibilityIdentifier("more.transfers")',
)
s = s.replace(
    'NavigationLink { V2DiscoverView(embedded: true) } label: { card("البحث", "ابحث عن نادي أو لاعب", "magnifyingglass") }',
    'NavigationLink { V2DiscoverView(embedded: true) } label: { card("البحث", "ابحث عن نادي أو لاعب", "magnifyingglass") }.accessibilityIdentifier("more.search")',
)
write(path, s)

# Open external editorial/statistics pages inside the app instead of handing the tap
# straight to another app. This gives the user deterministic feedback for every tap.
browser = ROOT / "Sources/Views/InAppWebLink.swift"
browser.write_text(
    '''import SwiftUI\nimport SafariServices\n\nstruct InAppWebLink<Label: View>: View {\n    let url: URL\n    private let label: () -> Label\n    @State private var presented = false\n\n    init(url: URL, @ViewBuilder label: @escaping () -> Label) {\n        self.url = url\n        self.label = label\n    }\n\n    var body: some View {\n        Button { presented = true } label: { label() }\n            .buttonStyle(.plain)\n            .sheet(isPresented: $presented) {\n                SafariContainer(url: url)\n                    .ignoresSafeArea()\n                    .presentationDragIndicator(.visible)\n            }\n    }\n}\n\nprivate struct SafariContainer: UIViewControllerRepresentable {\n    let url: URL\n    func makeUIViewController(context: Context) -> SFSafariViewController {\n        let controller = SFSafariViewController(url: url)\n        controller.preferredControlTintColor = UIColor(AppTheme.green)\n        controller.dismissButtonStyle = .close\n        return controller\n    }\n    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}\n}\n''',
    encoding="utf-8",
)

for path in [
    "Sources/Views/EnhancedNewsView.swift",
    "Sources/Views/EnhancedTransfersView.swift",
    "Sources/Views/PublicLeagueTableView.swift",
]:
    s = read(path)
    s = s.replace("Link(destination: url) {", "InAppWebLink(url: url) {")
    s = s.replace("Link(destination: itemURL) {", "InAppWebLink(url: itemURL) {")
    write(path, s)

path = "Sources/Views/V2LeagueHub.swift"
s = read(path)
s = s.replace(
    'Link("عرض إحصائيات البطولة لدى ESPN", destination: url).font(.subheadline.bold()).foregroundStyle(AppTheme.green).padding(16)',
    'InAppWebLink(url: url) { Text("عرض إحصائيات البطولة لدى ESPN").font(.subheadline.bold()).foregroundStyle(AppTheme.green).padding(16) }',
)
write(path, s)

# Expand the UI journey so CI proves the cards that users actually tap can open and
# return, rather than only checking a narrow happy path.
path = "UITests/ArabicJourneyTests.swift"
s = read(path)
if "testAllPrimaryNavigationCardsOpen" not in s:
    marker = "\n    @MainActor private func capture"
    test = r'''
    @MainActor func testAllPrimaryNavigationCardsOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["المزيد"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المزيد"].tap()

        func openAndBack(_ id: String, expectedText: String? = nil, expectedSearch: Bool = false) {
            let control = app.buttons[id]
            XCTAssertTrue(control.waitForExistence(timeout: 10), "Missing navigation control: \(id)")
            control.tap()
            if expectedSearch {
                XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "Search destination did not open")
            } else if let expectedText {
                XCTAssertTrue(app.staticTexts[expectedText].waitForExistence(timeout: 10), "Destination did not open: \(expectedText)")
            }
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10), "Back navigation missing after opening \(id)")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), "Failed to return from \(id)")
        }

        openAndBack("more.favorites", expectedText: "المتابعة")
        openAndBack("more.leagues", expectedText: "البطولات")
        openAndBack("more.transfers", expectedText: "أخبار الانتقالات")
        openAndBack("more.search", expectedSearch: true)

        app.tabBars.buttons["الرئيسية"].tap()
        XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 10))
        let league = app.buttons["home.league.307"]
        XCTAssertTrue(league.waitForExistence(timeout: 10))
        league.tap()
        XCTAssertTrue(app.staticTexts["ترتيب الموسم الحالي"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()

        let featured = app.buttons["home.featuredMatch"]
        if featured.waitForExistence(timeout: 5) {
            if !featured.isHittable { app.swipeUp() }
            featured.tap()
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 12), "Featured match did not open")
        }
    }
'''
    if marker not in s:
        raise RuntimeError("UI test insertion marker missing")
    s = s.replace(marker, test + marker, 1)
write(path, s)

print("navigation reliability fixes applied")
