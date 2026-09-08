import Foundation

struct V2PreferencesSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let booleans: [String: Bool]
    let integers: [String: Int]
    let strings: [String: String]
}

enum V2PreferencesBackup {
    static let schemaVersion = 1
    static let reminderLeadKey = "v2.reminderLeadMinutes"

    static let booleanKeys = [
        "v2.oledBlack",
        "v2.compactMatches",
        "v2.haptics",
        "v2.spoilerMode",
        "v2.lowDataMode",
        "v2.liveOnly",
        "v2.followedOnly",
        "v2.pinnedOnly",
        "v2.notifyGoals",
        "v2.notifyKickoff",
        "v2.notifyLineups",
        "v2.notifyRedCards"
    ]

    static let integerKeys = [reminderLeadKey]

    static let stringKeys = [
        "favoriteTeamIDs",
        "favoritePlayerIDs",
        "v2.pinnedMatchIDs",
        "v2.savedArticleIDs",
        "v2.mutedNewsSources"
    ]

    static func snapshot(defaults: UserDefaults = .standard, now: Date = Date()) -> V2PreferencesSnapshot {
        var booleans: [String: Bool] = [:]
        for key in booleanKeys {
            if defaults.object(forKey: key) != nil { booleans[key] = defaults.bool(forKey: key) }
        }

        var integers: [String: Int] = [:]
        for key in integerKeys {
            if defaults.object(forKey: key) != nil { integers[key] = defaults.integer(forKey: key) }
        }

        var strings: [String: String] = [:]
        for key in stringKeys {
            if let value = defaults.string(forKey: key), !value.isEmpty { strings[key] = value }
        }

        return V2PreferencesSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: now,
            booleans: booleans,
            integers: integers,
            strings: strings
        )
    }

    static func exportJSON(defaults: UserDefaults = .standard) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot(defaults: defaults))
        guard data.count <= 100_000 else { throw BackupError.payloadTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw BackupError.invalidPayload }
        return text
    }

    static func restore(_ json: String, defaults: UserDefaults = .standard) throws {
        let data = Data(json.utf8)
        guard !data.isEmpty, data.count <= 100_000 else { throw BackupError.payloadTooLarge }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value: V2PreferencesSnapshot
        do { value = try decoder.decode(V2PreferencesSnapshot.self, from: data) }
        catch { throw BackupError.invalidPayload }

        guard value.schemaVersion == schemaVersion else { throw BackupError.unsupportedSchema }
        guard Set(value.booleans.keys).isSubset(of: Set(booleanKeys)),
              Set(value.integers.keys).isSubset(of: Set(integerKeys)),
              Set(value.strings.keys).isSubset(of: Set(stringKeys)) else { throw BackupError.unknownKey }

        if let lead = value.integers[reminderLeadKey], !(5...120).contains(lead) {
            throw BackupError.invalidValue
        }
        guard value.strings.values.allSatisfy({ $0.count <= 20_000 }) else { throw BackupError.invalidValue }

        for (key, value) in value.booleans { defaults.set(value, forKey: key) }
        for (key, value) in value.integers { defaults.set(value, forKey: key) }
        for (key, value) in value.strings { defaults.set(value, forKey: key) }
    }

    /// Resets experience settings only. Followed teams/players, pinned matches and saved news stay intact.
    static func resetExperienceSettings(defaults: UserDefaults = .standard) {
        for key in booleanKeys + integerKeys { defaults.removeObject(forKey: key) }
    }

    enum BackupError: LocalizedError {
        case invalidPayload, payloadTooLarge, unsupportedSchema, unknownKey, invalidValue

        var errorDescription: String? {
            switch self {
            case .invalidPayload: return "النسخة الاحتياطية غير صالحة."
            case .payloadTooLarge: return "حجم النسخة الاحتياطية غير مقبول."
            case .unsupportedSchema: return "إصدار النسخة الاحتياطية غير مدعوم."
            case .unknownKey: return "النسخة تحتوي إعدادات غير معروفة لهذا الإصدار."
            case .invalidValue: return "النسخة تحتوي قيمة إعداد غير صالحة."
            }
        }
    }
}
