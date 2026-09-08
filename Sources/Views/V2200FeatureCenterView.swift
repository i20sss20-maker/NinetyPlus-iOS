import SwiftUI

struct V2200FeatureCenterView: View {
    @AppStorage(V2FeaturePreferences.oledBlack) private var oledBlack = false
    @AppStorage(V2FeaturePreferences.compactMatches) private var compactMatches = false
    @AppStorage(V2FeaturePreferences.haptics) private var haptics = true
    @AppStorage(V2FeaturePreferences.spoilerMode) private var spoilerMode = false
    @AppStorage(V2FeaturePreferences.lowDataMode) private var lowDataMode = false
    @AppStorage(V2FeaturePreferences.notifyGoals) private var notifyGoals = true
    @AppStorage(V2FeaturePreferences.notifyKickoff) private var notifyKickoff = true
    @AppStorage(V2FeaturePreferences.notifyLineups) private var notifyLineups = true
    @AppStorage(V2FeaturePreferences.notifyRedCards) private var notifyRedCards = true
    @AppStorage(V2FeaturePreferences.reminderLeadMinutes) private var reminderLeadMinutes = 30

    var body: some View {
        Form {
            Section("المظهر") {
                Toggle("OLED Black", isOn: $oledBlack)
                Toggle("عرض المباريات المضغوط", isOn: $compactMatches)
                Toggle("Haptics", isOn: $haptics)
            }
            Section("الخصوصية والاستهلاك") {
                Toggle("Spoiler Mode", isOn: $spoilerMode)
                Toggle("Low Data Mode", isOn: $lowDataMode)
            }
            Section("التنبيهات") {
                Toggle("بداية المباراة", isOn: $notifyKickoff)
                Toggle("الأهداف", isOn: $notifyGoals)
                Toggle("التشكيلة", isOn: $notifyLineups)
                Toggle("البطاقات الحمراء", isOn: $notifyRedCards)
                Picker("التذكير قبل المباراة", selection: $reminderLeadMinutes) {
                    Text("15 دقيقة").tag(15)
                    Text("30 دقيقة").tag(30)
                    Text("60 دقيقة").tag(60)
                }
            }
            Section("مبدأ البيانات") {
                Label("التحليلات المتقدمة تظهر فقط عند توفر بيانات حقيقية من المصدر.", systemImage: "checkmark.shield.fill")
                Label("لا يتم توليد xG أو Heat Map أو Shot Map بقيم وهمية.", systemImage: "chart.xyaxis.line")
            }
        }
        .navigationTitle("ميزات 90+")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: "ar-SA-u-ca-gregory-nu-latn"))
    }
}
