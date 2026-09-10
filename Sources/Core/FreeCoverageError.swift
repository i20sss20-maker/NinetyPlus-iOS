import Foundation

enum FreeCoverageError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "هذه التفاصيل غير متاحة في المصادر المجانية الحالية. بقية بيانات التطبيق تعمل بشكل مستقل."
    }
}
