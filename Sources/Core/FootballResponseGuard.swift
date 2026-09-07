import Foundation

/// Transport success alone does not mean the football request succeeded.
enum FootballResponseGuard {
    enum Failure: LocalizedError {
        case malformed, rejected
        var errorDescription: String? {
            switch self {
            case .malformed: return "تعذر قراءة بيانات المصدر. حاول مرة أخرى لاحقًا."
            case .rejected: return "مصدر البيانات لم يتمكن من تلبية هذا الطلب حاليًا. حاول لاحقًا."
            }
        }
    }

    static func validate(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any] else { throw Failure.malformed }
        for key in ["errors", "error"] {
            guard let value = envelope[key], !(value is NSNull) else { continue }
            if let dictionary = value as? [String: Any], dictionary.isEmpty { continue }
            if let array = value as? [Any], array.isEmpty { continue }
            if let text = value as? String, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            throw Failure.rejected
        }
        guard envelope["response"] != nil else { throw Failure.malformed }
    }
}
