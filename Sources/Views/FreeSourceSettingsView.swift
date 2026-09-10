import SwiftUI

struct FreeSourceSettingsView: View {
    @AppStorage(FreeSourceTransport.gatewayKey) private var savedURL = FreeSourceTransport.defaultGateway
    @State private var enteredURL = ""
    @State private var message: String?
    @State private var checks: [FreeConnectionCheck.Result] = []
    @State private var checking = false
    @State private var checkGeneration = 0
    @State private var checkedAt: Date?
    var body: some View {
        Form {
            Section("مصادر البيانات") {
                Label(savedURL.isEmpty ? "الوضع الحالي: اتصال مباشر" : "الوضع الحالي: عبر الخادم مع بديل مباشر", systemImage: "network")
                    .accessibilityIdentifier("sources.mode")
                Text("المباريات والترتيب والأندية: ESPN. ملفات اللاعبين: TheSportsDB. الأخبار: RSS. التغطية محدودة وقد تتأخر التحديثات.")
            }
            Section("فحص الاتصال من جهازك") {
                Button { checking = true; checkGeneration += 1 } label: {
                    HStack { Text("فحص الاتصال"); if checking { Spacer(); ProgressView() } }
                }.disabled(checking).accessibilityIdentifier("sources.check")
                ForEach(checks) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(result.title + (result.available ? " • متصل" : " • تعذّر الاتصال"), systemImage: result.available ? "checkmark.circle.fill" : "exclamationmark.triangle")
                            .foregroundStyle(result.available ? Color.green : Color.orange)
                        Text(result.message).font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("sources.result." + result.id)
                }
                if let checkedAt { Text("آخر فحص: \(FreeConnectionCheck.time(checkedAt)) بتوقيت الرياض").font(.caption) }
                Text("الفحص يستخدم إعداد الاتصال المحفوظ ويختبر بيانات المباريات، وليس استجابة الخادم فقط.").font(.caption).foregroundStyle(.secondary)
            }
            Section("البطولات المتاحة") {
                Text("السعودي • الإنجليزي • الإسباني • الإيطالي • الألماني • الفرنسي • دوري أبطال أوروبا")
                Text("التشكيلات والأحداث تظهر حين ينشرها المصدر. إحصائيات موسم اللاعب والهدافون وتنبيهات الأهداف غير متوفرة في هذه النسخة.").font(.caption).foregroundStyle(.secondary)
            }
            Section("خادم مجاني اختياري") {
                TextField("https://ninetyplus-free.…workers.dev", text: $enteredURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("sources.url")
                Button("حفظ الرابط") {
                    guard let url = FreeSourceTransport.gateway(enteredURL) else { message = "أدخل رابط HTTPS صحيحًا بدون مسار إضافي."; return }
                    savedURL = url.absoluteString; message = "تم حفظ رابط الخادم."
                }
                Button("استخدام الاتصال المباشر") { savedURL = ""; enteredURL = ""; message = "تم تفعيل الاتصال المباشر بالمصادر المجانية." }
                    .accessibilityIdentifier("sources.direct")
                Button("استعادة خادم 90+ الافتراضي") { savedURL = FreeSourceTransport.defaultGateway; enteredURL = savedURL; message = "تمت استعادة الخادم الافتراضي." }
                    .accessibilityIdentifier("sources.restore")
                if let message { Text(message).font(.caption) }
            }
        }
        .navigationTitle("مصادر البيانات").onAppear { enteredURL = savedURL }
        .onChange(of: savedURL) { _, _ in checks = []; checkedAt = nil; checkGeneration += 1 }
        .task(id: checkGeneration) {
            guard checkGeneration > 0 else { return }
            checking = true
            let results = await FreeConnectionCheck.run(gateway: savedURL)
            guard !Task.isCancelled else { return }
            checks = results; checkedAt = Date(); checking = false
        }
        .onDisappear { checking = false }
    }
}
