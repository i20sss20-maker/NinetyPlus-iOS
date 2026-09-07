import SwiftUI

struct EnhancedTransfersView: View {
    @StateObject private var store = EditorialStore.shared
    @State private var query = ""
    @State private var filter = "الكل"

    private var validTransfers: [RealArticle] {
        store.transfers.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.url != nil }
    }

    private var filtered: [RealArticle] {
        let source = validTransfers.filter { article in
            if !query.isEmpty && !article.title.localizedCaseInsensitiveContains(query) && !article.source.localizedCaseInsensitiveContains(query) { return false }
            switch filter {
            case "السعودية": return matchesSaudi(article.title)
            case "أوروبا": return matchesEurope(article.title)
            case "رسمي": return isOfficialish(article.title)
            case "شائعات": return isRumor(article.title)
            default: return true
            }
        }
        return source.sorted { $0.date > $1.date }
    }

    private var hasActiveFilter: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != "الكل" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TopBar(title: "مركز الانتقالات")
                    hero
                    sourceStatus
                    filters

                    if store.isLoading && validTransfers.isEmpty {
                        ProgressView("جاري تحديث سوق الانتقالات...")
                            .tint(AppTheme.green)
                            .padding(.top, 50)
                    } else if let error = store.errorMessage, validTransfers.isEmpty {
                        errorState(error)
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { item in transferCard(item) }
                    }
                }.padding(.bottom, 28)
            }
            .searchable(text: $query, prompt: "ابحث عن لاعب أو نادي أو مصدر")
            .refreshable { await store.refresh() }
            .task { await store.refreshIfStale(maxAge: 180) }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("سوق الانتقالات").font(.title2.bold())
                    Text("تغطية من مصادر فعلية مع تمييز الخبر حسب صياغته فقط").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                ZStack {
                    Circle().fill(AppTheme.green.opacity(0.14)).frame(width: 58, height: 58)
                    Image(systemName: "arrow.triangle.2.circlepath").font(.title2.bold()).foregroundStyle(AppTheme.green)
                }
            }
            HStack(spacing: 10) {
                statChip("الأخبار", value: "\(validTransfers.count)")
                statChip("آخر تحديث", value: store.lastUpdated.map { relative($0) } ?? "—")
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [AppTheme.card, AppTheme.card.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.green.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var sourceStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: store.errorMessage == nil ? "checkmark.shield.fill" : "clock.arrow.circlepath")
                .foregroundStyle(store.errorMessage == nil ? AppTheme.green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.errorMessage == nil ? "مصادر الانتقالات متصلة" : (validTransfers.isEmpty ? "تعذر تحديث الانتقالات" : "نعرض آخر بيانات محفوظة"))
                    .font(.caption.bold()).foregroundStyle(.white)
                if let lastUpdated = store.lastUpdated {
                    Text("آخر تحديث \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            Spacer()
            if store.isLoading { ProgressView().tint(AppTheme.green).scaleEffect(0.8) }
            else if store.errorMessage != nil {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(AppTheme.green)
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["الكل", "السعودية", "أوروبا", "رسمي", "شائعات"], id: \.self) { item in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { filter = item } } label: {
                        Text(item).font(.subheadline.bold()).foregroundStyle(filter == item ? .black : .white).padding(.horizontal, 14).padding(.vertical, 9).background(filter == item ? AppTheme.green : AppTheme.card, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 42)).foregroundStyle(.orange)
            Text("تعذر جلب أخبار الانتقالات").font(.headline)
            Text(message).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button { Task { await store.refresh() } } label: {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                    .font(.subheadline.bold()).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(AppTheme.green, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16).padding(.top, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle").font(.system(size: 44)).foregroundStyle(AppTheme.green)
            Text(hasActiveFilter ? "لا توجد نتائج مطابقة" : "لا توجد أخبار انتقالات متاحة الآن").font(.headline)
            Text(hasActiveFilter ? "غيّر البحث أو الفلتر لعرض نتائج أخرى." : "اسحب الصفحة للتحديث أو جرّب مرة أخرى بعد قليل.")
                .font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            if hasActiveFilter {
                Button {
                    query = ""
                    filter = "الكل"
                } label: {
                    Label("مسح الفلاتر", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                }.buttonStyle(.plain)
            }
        }.padding(.top, 60)
    }

    private func transferCard(_ item: RealArticle) -> some View {
        Group {
            if let url = item.url {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            badge(for: item.title)
                            Text(item.source.isEmpty ? "مصدر إخباري" : item.source).font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(1)
                            Spacer()
                            Text(item.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                        Text(item.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading).lineSpacing(3)
                        HStack {
                            Label(category(for: item.title), systemImage: icon(for: item.title)).font(.caption).foregroundStyle(AppTheme.muted)
                            Spacer()
                            Label("المصدر الأصلي", systemImage: "arrow.up.right.square").font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                    .padding(16)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    .padding(.horizontal, 16)
                }.buttonStyle(.plain)
            }
        }
    }

    private func badge(for title: String) -> some View {
        let text = isOfficialish(title) ? "رسمي" : (isRumor(title) ? "تقارير" : "انتقال")
        return Text(text).font(.caption2.bold()).foregroundStyle(isOfficialish(title) ? .black : .white).padding(.horizontal, 8).padding(.vertical, 4).background(isOfficialish(title) ? AppTheme.green : AppTheme.soft.opacity(0.65), in: Capsule())
    }
    private func statChip(_ title: String, value: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.headline); Text(title).font(.caption2).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14)) }
    private func relative(_ date: Date) -> String { let formatter = RelativeDateTimeFormatter(); formatter.locale = Locale(identifier: "ar"); formatter.unitsStyle = .short; return formatter.localizedString(for: date, relativeTo: Date()) }
    private func isOfficialish(_ title: String) -> Bool { let t = title.lowercased(); return ["رسمي", "official", "announces", "signs", "joins", "يعلن", "يتعاقد", "تعاقد", "ضم"].contains { t.contains($0) } }
    private func isRumor(_ title: String) -> Bool { let t = title.lowercased(); return ["تقارير", "مصادر", "قريب", "مفاوض", "يرغب", "اهتمام", "report", "rumor", "linked", "talks", "interest"].contains { t.contains($0) } }
    private func matchesSaudi(_ title: String) -> Bool { let t = title.lowercased(); return ["السعود", "روشن", "الهلال", "النصر", "الاتحاد", "الأهلي", "القادسية", "riyadh", "hilal", "nassr", "ittihad", "ahli", "saudi"].contains { t.contains($0) } }
    private func matchesEurope(_ title: String) -> Bool { let t = title.lowercased(); return ["premier", "laliga", "serie a", "bundesliga", "ligue 1", "champions", "real madrid", "barcelona", "liverpool", "arsenal", "chelsea", "manchester", "bayern", "inter", "milan", "psg"].contains { t.contains($0) } }
    private func category(for title: String) -> String { if isOfficialish(title) { return "إعلان أو صفقة معلنة في صياغة المصدر" }; if isRumor(title) { return "تقارير ومفاوضات" }; return "أخبار سوق الانتقالات" }
    private func icon(for title: String) -> String { if isOfficialish(title) { return "checkmark.seal.fill" }; if isRumor(title) { return "bubble.left.and.text.bubble.right" }; return "arrow.left.arrow.right" }
}
