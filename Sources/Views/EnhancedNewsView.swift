import SwiftUI

struct EnhancedNewsView: View {
    @StateObject private var store = EditorialStore.shared
    @State private var query = ""
    @State private var filter = "الكل"

    private var validNews: [RealArticle] {
        store.news.filter { article in
            !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && article.url != nil
        }
    }

    private var filtered: [RealArticle] {
        let searched = query.isEmpty ? validNews : validNews.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.source.localizedCaseInsensitiveContains(query)
        }
        switch filter {
        case "السعودية":
            return searched.filter { article in
                let t = article.title.lowercased()
                return t.contains("السعود") || t.contains("الهلال") || t.contains("النصر") || t.contains("الاتحاد") || t.contains("الأهلي") || t.contains("روشن")
            }.sorted { $0.date > $1.date }
        case "الانتقالات":
            return searched.filter { article in
                let t = article.title.lowercased()
                return t.contains("انتقال") || t.contains("صفقة") || t.contains("تعاقد") || t.contains("transfer")
            }.sorted { $0.date > $1.date }
        default:
            return searched.sorted { $0.date > $1.date }
        }
    }

    private var hero: RealArticle? { filtered.first }
    private var remaining: [RealArticle] { Array(filtered.dropFirst()) }
    private var hasActiveFilter: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != "الكل" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TopBar(title: "الأخبار")
                    sourceStatus
                    filters

                    if store.isLoading && validNews.isEmpty {
                        ProgressView("جاري جلب أحدث الأخبار...")
                            .tint(AppTheme.green)
                            .padding(.top, 80)
                    } else if let error = store.errorMessage, validNews.isEmpty {
                        errorState(error)
                    } else if let hero {
                        heroCard(hero)
                        sectionHeader
                        ForEach(remaining) { article in
                            articleRow(article)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.bottom, 28)
            }
            .searchable(text: $query, prompt: "ابحث في الأخبار والمصادر")
            .refreshable { await store.refresh() }
            .task { await store.refreshIfStale(maxAge: 180) }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var sourceStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: store.errorMessage == nil ? "checkmark.shield.fill" : "clock.arrow.circlepath")
                .foregroundStyle(store.errorMessage == nil ? AppTheme.green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.errorMessage == nil ? "أخبار من مصادر فعلية" : (validNews.isEmpty ? "تعذر تحديث الأخبار" : "نعرض آخر أخبار محفوظة"))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                if let lastUpdated = store.lastUpdated {
                    Text("آخر تحديث \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
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
            HStack(spacing: 10) {
                ForEach(["الكل", "الأحدث", "السعودية", "الانتقالات"], id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = item }
                    } label: {
                        Text(item)
                            .font(.subheadline.bold())
                            .foregroundStyle(filter == item ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(filter == item ? AppTheme.green : AppTheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("آخر الأخبار").font(.title3.bold())
            Spacer()
            Text("\(filtered.count)").font(.caption.bold()).foregroundStyle(AppTheme.green)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 42)).foregroundStyle(.orange)
            Text("تعذر جلب الأخبار").font(.headline)
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
        .padding(.horizontal, 16).padding(.top, 30)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper").font(.system(size: 44)).foregroundStyle(AppTheme.green)
            Text(hasActiveFilter ? "لا توجد أخبار مطابقة" : "لا توجد أخبار متاحة الآن").font(.headline)
            Text(hasActiveFilter ? "غيّر البحث أو التصنيف لعرض نتائج أخرى." : "اسحب الصفحة للتحديث أو جرّب مرة أخرى بعد قليل.")
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
        }.padding(.top, 70)
    }

    private func heroCard(_ article: RealArticle) -> some View {
        Group {
            if let url = article.url {
                Link(destination: url) { heroContent(article) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func heroContent(_ article: RealArticle) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.22)], startPoint: .topTrailing, endPoint: .bottomLeading)
                .frame(height: 240)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").foregroundStyle(.black)
                    Text("أبرز خبر").font(.caption.bold()).foregroundStyle(.black)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.green, in: Capsule())
                Spacer()
                Text(article.title).font(.title3.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(4)
                HStack {
                    Label(article.source.isEmpty ? "مصدر إخباري" : article.source, systemImage: "link.circle.fill")
                        .font(.caption.bold()).foregroundStyle(AppTheme.green)
                    Spacer()
                    Text(article.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.green.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func articleRow(_ article: RealArticle) -> some View {
        if let url = article.url {
            Link(destination: url) {
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(AppTheme.green.opacity(0.12))
                        Image(systemName: icon(for: article.title)).font(.title3.bold()).foregroundStyle(AppTheme.green)
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(3)
                        HStack(spacing: 7) {
                            Text(article.source.isEmpty ? "مصدر إخباري" : article.source).font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(1)
                            Text("•").foregroundStyle(AppTheme.muted)
                            Text(article.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                            Spacer()
                            Image(systemName: "arrow.up.right.square").foregroundStyle(AppTheme.muted)
                        }
                    }
                }
                .padding(14)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }

    private func icon(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("انتقال") || t.contains("صفقة") || t.contains("تعاقد") || t.contains("transfer") { return "arrow.left.arrow.right" }
        if t.contains("إصابة") || t.contains("اصابة") { return "cross.case.fill" }
        if t.contains("مدرب") { return "person.badge.shield.checkmark.fill" }
        if t.contains("هدف") || t.contains("فوز") || t.contains("مباراة") { return "soccerball" }
        return "newspaper.fill"
    }
}
