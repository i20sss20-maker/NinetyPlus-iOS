import Foundation

enum FootballResponseGuard {
    enum Failure: LocalizedError {
        case malformed, rejected, planRestricted
        var errorDescription: String? {
            switch self {
            case .malformed: return "تعذر قراءة بيانات المصدر. حاول مرة أخرى لاحقًا."
            case .rejected: return "تعذر الحصول على هذه التفاصيل من المصدر حاليًا."
            case .planRestricted: return "هذه التفاصيل غير مشمولة في خطة مصدر البيانات الحالية. لا نعرض بيانات موسم سابق بدلًا منها."
            }
        }
    }
    static func validate(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data), let envelope = object as? [String: Any] else { throw Failure.malformed }
        for key in ["errors", "error"] {
            guard let value = envelope[key], !(value is NSNull) else { continue }
            if let dictionary = value as? [String: Any] {
                if dictionary.isEmpty { continue }
                if dictionary["plan"] != nil { throw Failure.planRestricted }
            }
            if let array = value as? [Any], array.isEmpty { continue }
            if let text = value as? String, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            throw Failure.rejected
        }
        guard envelope["response"] != nil else { throw Failure.malformed }
    }
}
