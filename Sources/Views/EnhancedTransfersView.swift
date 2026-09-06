import SwiftUI

struct EnhancedTransfersView: View {
    @StateObject private var store = SportsStore.shared
    @State private var query = ""
    @State private var filter = "الكل"

    private var filtered: [RealArticle] {
        let source = store.transfers.filter { article in
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TopBar(title: "مركز الانتقالات")

                    hero
                    filters

                    if store.isLoading && store.transfers.isEmpty {
                        ProgressView("جاري تحديث سوق الانتقالات...")
                            .tint(AppTheme.green)
                            .padding(.top, 50)
                    } else if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.left.arrow.right.circle")
                                .font(.system(size: 44))
                                .foregroundStyle(AppTheme.green)
                            Text("لا توجد نتائج مطابقة الآن")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(filtered) { item in
                            transferCard(item)
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .searchable(text: $query, prompt: "ابحث عن لاعب أو نادي أو مصدر")
            .refreshable { await store.refresh() }
            .task { if store.transfers.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("سوق الانتقالات")
                        .font(.title2.bold())
                    Text("تغطية من مصادر فعلية مع تمييز الخبر حسب صياغته فقط")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                ZStack {
                    Circle().fill(AppTheme.green.opacity(0.14)).frame(width: 58, height: 58)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.green)
                }
            }

            HStack(spacing: 10) {
                statChip("الأخبار", value: "\(store.transfers.count)")
                statChip("آخر تحديث", value: store.lastUpdated.map { relative($0) } ?? "—")
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [AppTheme.card, AppTheme.card.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.green.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["الكل", "السعودية", "أوروبا", "رسمي", "شائعات"], id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = item }
                    } label: {
                        Text(item)
                            .font(.subheadline.bold())
                            .foregroundStyle(filter == item ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(filter == item ? AppTheme.green : AppTheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func transferCard(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    badge(for: item.title)
                    Text(item.source.isEmpty ? "مصدر إخباري" : item.source)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.green)
                        .lineLimit(1)
                    Spacer()
                    Text(item.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }

                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)

                HStack {
                    Label(category(for: item.title), systemImage: icon(for: item.title))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    Label("المصدر الأصلي", systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(16)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.05), lineWidth: 1))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private func badge(for title: String) -> some View {
        let text = isOfficialish(title) ? "رسمي" : (isRumor(title) ? "تقارير" : "انتقال")
        return Text(text)
            .font(.caption2.bold())
            .foregroundStyle(isOfficialish(title) ? .black : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOfficialish(title) ? AppTheme.green : AppTheme.soft.opacity(0.65), in: Capsule())
    }

    private func statChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func isOfficialish(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["رسمي", "official", "announces", "signs", "joins", "يعلن", "يتعاقد", "تعاقد", "ضم"].contains { t.contains($0) }
    }

    private func isRumor(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["تقارير", "مصادر", "قريب", "مفاوض", "يرغب", "اهتمام", "report", "rumor", "linked", "talks", "interest"].contains { t.contains($0) }
    }

    private func matchesSaudi(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["السعود", "روشن", "الهلال", "النصر", "الاتحاد", "الأهلي", "القادسية", "riyadh", "hilal", "nassr", "ittihad", "ahli", "saudi"].contains { t.contains($0) }
    }

    private func matchesEurope(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["premier", "laliga", "serie a", "bundesliga", "ligue 1", "champions", "real madrid", "barcelona", "liverpool", "arsenal", "chelsea", "manchester", "bayern", "inter", "milan", "psg"].contains { t.contains($0) }
    }

    private func category(for title: String) -> String {
        if isOfficialish(title) { return "إعلان أو صفقة معلنة في صياغة المصدر" }
        if isRumor(title) { return "تقارير ومفاوضات" }
        return "أخبار سوق الانتقالات"
    }

    private func icon(for title: String) -> String {
        if isOfficialish(title) { return "checkmark.seal.fill" }
        if isRumor(title) { return "bubble.left.and.text.bubble.right" }
        return "arrow.left.arrow.right"
    }
}
