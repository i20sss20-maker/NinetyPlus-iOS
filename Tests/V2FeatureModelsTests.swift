import Foundation

@main struct V2FeatureModelsTests {
    static var assertions = 0
    static func check(_ value: Bool, _ message: String) {
        assertions += 1
        guard value else { fatalError(message) }
    }
    static func main() throws {
        for kind in [V2ContentRoute.Kind.match, .team, .player, .league] {
            let route = V2ContentRoute(kind: kind, identifier: "123")!
            check(V2ContentRoute(url: route.url!) == route, "numeric route must round trip")
        }
        let canonical = V2ContentRoute(kind: .match, identifier: "np:2026-09-08:test", kickoff: Date(timeIntervalSince1970: 1788896658))!
        check(V2ContentRoute(url: canonical.url!) == canonical, "canonical date route must round trip")
        check(canonical.url!.absoluteString.contains("%3A"), "ID must be percent encoded")
        for raw in ["http://match/123", "ninetyplus://unknown/123", "ninetyplus://match/", "ninetyplus://match/0", "ninetyplus://team/espn:12", "ninetyplus://player/np:abc", "ninetyplus://match/123/456", "ninetyplus://match/np:a%2Fb", "ninetyplus://match/123#bad", "ninetyplus://u:p@match/123", "ninetyplus://match:80/123", "ninetyplus://match/1?kickoff=nan", "ninetyplus://match/1?kickoff=1&kickoff=2", "ninetyplus://team/1?kickoff=2", "ninetyplus://match/1?x=2", "ninetyplus://match/1?kickoff=-1", "ninetyplus://match/1?kickoff=999999999999"] {
            check(V2ContentRoute(url: URL(string: raw)!) == nil, "invalid route accepted: \(raw)")
        }
        check(V2ContentRoute(kind: .team, identifier: "00012")?.identifier == "12", "numeric ID normalization")
        check(V2ContentRoute(kind: .match, identifier: "np:") == nil, "empty namespace suffix")
        check(V2ContentRoute(kind: .match, identifier: "np:a b") == nil, "space in ID")
        check(V2ContentRoute(kind: .match, identifier: String(repeating: "a", count: 241)) == nil, "oversized ID")
        check(V2ContentRoute(kind: .match, identifier: "1")!.id != V2ContentRoute(kind: .match, identifier: "1", kickoff: Date(timeIntervalSince1970: 0))!.id, "unknown and epoch kickoff have distinct presentation identities")
        var library = V2LineupLibrary()
        check(try V2LineupLibrary.decode("").drafts.isEmpty, "new empty library")
        var draft = V2LineupDraft()
        draft.title = "الاتحاد"
        draft.names[0] = "حارس"
        try library.save(draft)
        check(library.selected?.names[0] == "حارس", "save draft")
        check(try V2LineupLibrary.decode(library.encoded()) == library, "persistent round trip")
        draft.names[1] = "مدافع"
        try library.save(draft)
        check(library.drafts.count == 1 && library.selected?.filledCount == 2, "same ID updates in place")
        for formation in V2LineupDraft.formations {
            draft.formation = formation
            check(draft.rows.flatMap { $0 } == Array(0..<11), "formation contains exactly 11 positions")
        }
        var other = V2LineupDraft(); other.title = "الثانية"
        try library.save(other)
        library.select(draft.id)
        check(library.selected?.id == draft.id, "select saved draft")
        library.remove(draft.id)
        check(library.drafts.count == 1 && library.selected?.id == other.id, "delete selects existing draft")
        library.remove(other.id)
        check(library.selected == nil && library.drafts.isEmpty, "delete last draft")
        for _ in 0..<V2LineupLibrary.limit { try library.save(V2LineupDraft()) }
        do { try library.save(V2LineupDraft()); fatalError("library limit missing") }
        catch V2LineupLibrary.StorageError.full { assertions += 1 }
        var invalid = V2LineupDraft(); invalid.names = []
        check(!invalid.isValid, "malformed draft rejected")
        do { _ = try V2LineupLibrary.decode("broken"); fatalError("corrupt data accepted") } catch { assertions += 1 }
        var object = try JSONSerialization.jsonObject(with: Data(library.encoded().utf8)) as! [String: Any]
        object["version"] = 2
        let future = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        do { _ = try V2LineupLibrary.decode(future); fatalError("future schema accepted") } catch { assertions += 1 }
        check(draft.shareText.contains("ليست تشكيلة رسمية"), "user-generated lineup truth label")
        check(V2ComparisonMath.per90(count: nil, minutes: 90) == nil, "nil remains unknown")
        check(V2ComparisonMath.per90(count: 3, minutes: 0) == nil, "no division by zero")
        check(V2ComparisonMath.per90(count: -1, minutes: 90) == nil, "negative count rejected")
        check(V2ComparisonMath.per90(count: 3, minutes: 180) == 1.5, "per90 calculation")
        check(V2ComparisonMath.per90(count: 0, minutes: 90) == 0, "known zero preserved")
        check(V2ComparisonMath.display(Double.nan) == "—", "nonfinite hidden")
        check(V2ComparisonMath.display(1.5) == "1.50", "stable Latin format")
        check(V2ComparisonMath.display(nil as Int?) == "—", "missing stat never zero")
        print("V2 feature models: \(assertions) assertions passed")
    }
}
