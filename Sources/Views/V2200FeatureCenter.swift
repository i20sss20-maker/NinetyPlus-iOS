import SwiftUI

struct V2200FeatureCenterView: View {
    @AppStorage(V2FeaturePreferences.oledBlack) private var oledBlack = false
    @AppStorage(V2FeaturePreferences.compactMatches) private var compactMatches = false
    @AppStorage(V2FeaturePreferences.haptics) private var haptics = true
    @AppStorage(V2FeaturePreferences.spoilerMode) private var spoilerMode = false
    @AppStorage(V2FeaturePreferences.lowDataMode) private var lowDataMode = false
    @AppStorage(V2FeaturePreferences.liveOnly) private var liveOnly = false
    @AppStorage(V2FeaturePreferences.followedOnly) private var followedOnly = false
    @AppStorage(V2FeaturePreferences.pinnedOnly) private var pinnedOnly = false
    @AppStorage(V2FeaturePreferences.reminderLeadMinutes) private var reminderLeadMinutes = 30
    @AppStorage(V2FeaturePreferences.notifyGoals) private var notifyGoals = true
    @AppStorage(V2FeaturePreferences.notifyKickoff) private var notifyKickoff = true
    @AppStorage(V2FeaturePreferences.notifyLineups) private var notifyLineups = true
    @AppStorage(V2FeaturePreferences.notifyRedCards) private var notifyRedCards = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "مركز ميزات 90+", subtitle: "تخصيص التجربة والميزات المتقدمة")
                section("العرض") {
                    toggle("OLED Black", "خلفية سوداء حقيقية للشاشات OLED", "moon.stars.fill", $oledBlack)
                    toggle("عرض مضغوط", "بطاقات مباريات أصغر ومعلومات أكثر على الشاشة", "rectangle.compress.vertical", $compactMatches)
                    toggle("اهتزازات Haptic", "تأكيدات لمس عند التثبيت والمتابعة", "iphone.radiowaves.left.and.right", $haptics)
                    toggle("إخفاء النتائج", "Spoiler Mode للمشاهدة لاحقًا", "eye.slash.fill", $spoilerMode)
                    toggle("توفير البيانات", "يقلل الصور والتحميلات غير الضرورية", "antenna.radiowaves.left.and.right.slash", $lowDataMode)
                }

                section("المباريات") {
                    toggle("المباشر فقط", "فلتر افتراضي للمباريات المباشرة", "dot.radiowaves.left.and.right", $liveOnly)
                    toggle("متابعاتي فقط", "يعرض أندية المتابعة عند تفعيل الفلتر", "star.fill", $followedOnly)
                    toggle("المثبتة فقط", "يركز على المباريات التي ثبتها المستخدم", "pin.fill", $pinnedOnly)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("تذكير قبل المباراة", systemImage: "bell.badge.fill")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                            Spacer()
                            Text("\(reminderLeadMinutes) دقيقة".englishDigits)
                                .font(.caption.bold()).foregroundStyle(AppTheme.green)
                        }
                        Slider(value: Binding(get: { Double(reminderLeadMinutes) }, set: { reminderLeadMinutes = Int($0) }), in: 5...120, step: 5)
                            .tint(AppTheme.green)
                    }
                    .padding(.vertical, 8)
                }

                section("التنبيهات") {
                    toggle("بداية المباراة", "إشعار عند انطلاق المباراة", "play.circle.fill", $notifyKickoff)
                    toggle("الأهداف", "إشعار عند تغير النتيجة", "soccerball", $notifyGoals)
                    toggle("التشكيلة", "عند توفر التشكيلة الرسمية", "person.3.fill", $notifyLineups)
                    toggle("البطاقات الحمراء", "تنبيه للأحداث المؤثرة", "rectangle.fill", $notifyRedCards)
                }

                section("سياسة البيانات") {
                    info("الأرقام", "0–9 دائمًا", "textformat.123")
                    info("التحليلات", "تظهر فقط عند توفر بيانات حقيقية", "chart.xyaxis.line")
                    info("xG / الخرائط", "Data-gated — بدون أرقام أو خرائط وهمية", "scope")
                    info("Fallback", "Railway canonical + مصادر احتياطية", "arrow.triangle.2.circlepath")
                }
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("ميزات 90+")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.white)
            VStack(spacing: 4) { content() }
                .padding(14)
                .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border))
        }
        .padding(.horizontal, 16)
    }

    private func toggle(_ title: String, _ subtitle: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(AppTheme.green).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                    Text(subtitle).font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
        }
        .tint(AppTheme.green)
        .padding(.vertical, 7)
        .onChange(of: binding.wrappedValue) { _, _ in V2Haptics.impact() }
    }

    private func info(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.green).frame(width: 30)
            Text(title).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text(value).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
    }
}
