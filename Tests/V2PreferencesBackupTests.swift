import Foundation

@main
struct V2PreferencesBackupTests {
    static func main() throws {
        let suite = "ninetyplus.backup.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "v2.spoilerMode")
        defaults.set(false, forKey: "v2.lowDataMode")
        defaults.set(30, forKey: V2PreferencesBackup.reminderLeadKey)
        defaults.set("10,20", forKey: "favoriteTeamIDs")
        defaults.set("m1,m2", forKey: "v2.pinnedMatchIDs")
        defaults.set("news-a,news-b", forKey: "v2.savedArticleIDs")

        let json = try V2PreferencesBackup.exportJSON(defaults: defaults)
        assert(json.contains("favoriteTeamIDs"))
        assert(!json.lowercased().contains("api_key"))
        assert(!json.lowercased().contains("apikey"))

        defaults.removePersistentDomain(forName: suite)
        try V2PreferencesBackup.restore(json, defaults: defaults)
        assert(defaults.bool(forKey: "v2.spoilerMode") == true)
        assert(defaults.integer(forKey: V2PreferencesBackup.reminderLeadKey) == 30)
        assert(defaults.string(forKey: "favoriteTeamIDs") == "10,20")
        assert(defaults.string(forKey: "v2.pinnedMatchIDs") == "m1,m2")

        V2PreferencesBackup.resetExperienceSettings(defaults: defaults)
        assert(defaults.object(forKey: "v2.spoilerMode") == nil)
        assert(defaults.object(forKey: V2PreferencesBackup.reminderLeadKey) == nil)
        assert(defaults.string(forKey: "favoriteTeamIDs") == "10,20")
        assert(defaults.string(forKey: "v2.pinnedMatchIDs") == "m1,m2")

        let badSchema = json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        do {
            try V2PreferencesBackup.restore(badSchema, defaults: defaults)
            assertionFailure("unsupported schema should fail")
        } catch V2PreferencesBackup.BackupError.unsupportedSchema {
            // expected
        }

        print("V2PreferencesBackupTests: PASS")
    }
}
