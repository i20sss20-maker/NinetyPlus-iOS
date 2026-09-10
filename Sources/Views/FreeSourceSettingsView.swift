import SwiftUI

struct FreeSourceSettingsView: View {
    @AppStorage(FreeSourceTransport.gatewayKey) private var savedURL = ""
    @State private var enteredURL = ""
    @State private var message: String?
    var body: some View {
        Form {
            Section("مصادر البيانات") {
                Text("التطبيق متصل مباشرة بالمصادر المجانية. يمكنك إضافة خادم Cloudflare الخاص بك بعد نشره، وسيعود التطبيق للاتصال المباشر إذا تعذر الوصول إليه.")
                Text("المباريات والترتيب والأندية: ESPN. ملفات اللاعبين: TheSportsDB. الأخبار: RSS. التغطية محدودة وقد تتأخر التحديثات.")
            }
            Section("خادم مجاني اختياري") {
                TextField("https://ninetyplus-free.…workers.dev", text: $enteredURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .environment(\.layoutDirection, .leftToRight)
                Button("حفظ الرابط") {
                    guard let url = FreeSourceTransport.gateway(enteredURL) else { message = "أدخل رابط HTTPS صحيحًا بدون مسار إضافي."; return }
                    savedURL = url.absoluteString; message = "تم حفظ رابط الخادم."
                }
                Button("استخدام الاتصال المباشر") { savedURL = ""; enteredURL = ""; message = "تم تفعيل الاتصال المباشر بالمصادر المجانية." }
                if let message { Text(message).font(.caption) }
            }
        }
        .navigationTitle("مصادر البيانات").onAppear { enteredURL = savedURL }
    }
}
