import SwiftUI
import UIKit

struct V2PreferencesBackupView: View {
    @State private var payload = ""
    @State private var status: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "النسخ والاستعادة", subtitle: "إعدادات 90+ والمتابعات فقط")

                VStack(alignment: .leading, spacing: 10) {
                    Label("نسخة محلية", systemImage: "lock.shield.fill")
                        .font(.headline).foregroundStyle(AppTheme.green)
                    Text("لا تشمل النسخة مفاتيح API أو أي أسرار. تشمل تفضيلات العرض والتنبيهات، الأندية واللاعبين المتابعين، المباريات المثبتة، الأخبار المحفوظة والمصادر المكتومة.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
                .padding(.horizontal, 16)

                TextEditor(text: $payload)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 230)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("settings.backupPayload")

                VStack(spacing: 10) {
                    Button { createBackup() } label: {
                        actionRow("إنشاء نسخة احتياطية", "doc.badge.plus")
                    }
                    Button { copyPayload() } label: {
                        actionRow("نسخ النص", "doc.on.doc")
                    }
                    .disabled(payload.isEmpty)
                    Button { restoreBackup() } label: {
                        actionRow("استعادة من النص", "arrow.clockwise.icloud")
                    }
                    .disabled(payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(role: .destructive) { resetExperience() } label: {
                        actionRow("إعادة إعدادات التجربة للوضع الافتراضي", "arrow.counterclockwise")
                    }
                }
                .padding(.horizontal, 16)

                if let status {
                    Label(status, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(isError ? .orange : AppTheme.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background((isError ? Color.orange : AppTheme.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("النسخ والاستعادة")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.backupRestore")
    }

    private func actionRow(_ title: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.subheadline.bold())
            Spacer()
            Image(systemName: "chevron.left").font(.caption)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    @MainActor private func createBackup() {
        do {
            payload = try V2PreferencesBackup.exportJSON()
            status = "تم إنشاء النسخة. تقدر تنسخ النص وتحفظه في مكان آمن."
            isError = false
            V2Haptics.success()
        } catch {
            status = error.localizedDescription
            isError = true
        }
    }

    @MainActor private func copyPayload() {
        guard !payload.isEmpty else { return }
        UIPasteboard.general.string = payload
        status = "تم نسخ النسخة الاحتياطية."
        isError = false
        V2Haptics.success()
    }

    @MainActor private func restoreBackup() {
        do {
            try V2PreferencesBackup.restore(payload)
            status = "تمت الاستعادة بنجاح. التغييرات تطبق مباشرة أو عند إعادة فتح الشاشة."
            isError = false
            V2Haptics.success()
        } catch {
            status = error.localizedDescription
            isError = true
        }
    }

    @MainActor private func resetExperience() {
        V2PreferencesBackup.resetExperienceSettings()
        status = "تمت إعادة إعدادات التجربة فقط. متابعاتك ومثبتاتك ومحفوظات الأخبار ما زالت محفوظة."
        isError = false
        V2Haptics.success()
    }
}
