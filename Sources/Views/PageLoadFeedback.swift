import SwiftUI

/// Shared loading/error feedback. Existing content remains below this view.
struct PageLoadFeedback: View {
    let loading: Bool
    let hasValue: Bool
    let message: String?
    let updatedAt: Date?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if loading {
                ProgressView(hasValue ? "جاري التحديث..." : "جاري تحميل البيانات...")
                    .tint(AppTheme.green)
                    .font(.subheadline)
                    .padding(.vertical, hasValue ? 8 : 28)
            }
            if let message {
                VStack(spacing: 10) {
                    Label(hasValue ? "تعذر تحديث بعض البيانات" : "تعذر تحميل البيانات", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                    if hasValue {
                        Text("نعرض آخر بيانات متاحة في هذه الصفحة.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Button(action: retry) {
                        Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(AppTheme.green, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
            if hasValue, let updatedAt {
                Text("آخر جلب ناجح \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
    }
}
