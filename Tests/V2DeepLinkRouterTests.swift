import Foundation

@main
struct V2DeepLinkRouterTests {
    static func main() {
        let cases: [(String, Int?)] = [
            ("ninetyplus://home", 0),
            ("ninetyplus://matches", 1),
            ("ninetyplus://search", 2),
            ("ninetyplus://news", 3),
            ("ninetyplus://more", 4),
            ("https://example.com/matches", nil),
            ("ninetyplus://unknown", nil)
        ]
        for (raw, expected) in cases {
            guard let url = URL(string: raw) else { fatalError("bad test URL: \(raw)") }
            let actual = V2DeepLinkRouter.tab(for: url)
            precondition(actual == expected, "\(raw): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
        print("V2DeepLinkRouterTests passed: \(cases.count)")
    }
}
