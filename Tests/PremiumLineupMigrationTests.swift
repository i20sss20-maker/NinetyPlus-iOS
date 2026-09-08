import Foundation

@main struct PremiumLineupMigrationTests {
    static func main() throws {
        var draft = V2LineupDraft()
        draft.names[0] = "الحارس"
        let encoded = try JSONEncoder().encode(draft)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "captainIndex"); object.removeValue(forKey: "bench")
        let old = try JSONDecoder().decode(V2LineupDraft.self, from: JSONSerialization.data(withJSONObject: object))
        precondition(old.captainIndex == nil && old.bench == nil && old.isValid)
        draft.captainIndex = 0; draft.bench = ["البديل"]
        precondition(draft.isValid && draft.shareText.contains("الحارس") && draft.shareText.contains("البديل"))
        var library = V2LineupLibrary(); try library.save(draft)
        let restored = try V2LineupLibrary.decode(library.encoded())
        precondition(restored.selected == draft)
        draft.captainIndex = 11; precondition(!draft.isValid)
        draft.captainIndex = nil; draft.bench = Array(repeating: "بديل", count: 10); precondition(!draft.isValid)
        print("Premium lineup migration: old-library compatibility, captain/bench persistence and bounds passed")
    }
}
