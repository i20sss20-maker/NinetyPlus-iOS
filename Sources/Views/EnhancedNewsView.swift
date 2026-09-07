import SwiftUI

struct EnhancedNewsView: View {
    @StateObject private var store = EditorialStore.shared
    @State private var query = ""
    @State private var filter = "الكل"

    private var validNews: [RealArticle] {
        store.news.filter { article in
            guard !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = article.url, let host = url.host, !host.isEmpty else { return false }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        }
    }

    private var filtered: [RealArticle] {
        let searched = query.isEmpty ? validNews : validNews.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query)
        }
        let result: [RealArticle]
        switch filter {
        case "السعودية":
            result = searched.filter { article in
                let t = article.title.lowercased()
                return ["السعود", "الهلال", "النصر", "الاتحاد", "الأهلي", "روشن"].contains { t.contains($0) }
            }
        case "الانتقالات":
            result = searched.filter { article in
                let t = article.title.lowercased()
                return ["انتقال", "صفقة", "تعاقد", "transfer"].contains { t.contains($0) }
            }
        default: result = searched
        }
        return result.sorted { $0.date > $1.date }
    }

    private var hero: RealArticle? { filtered.first }
    private var remaining: [RealArticle] { Array(filtered.dropFirst()) }
    private var hasActiveFilter: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != "الكل" }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    TopBar(title: "الأخبار", subtitle: "آخر الأخبار من مصادر فعلية")
                    sourceStatus
                    filters
                    if store.isLoading && validNews.isEmpty {
                        ProgressView("جاري جلب أحدث الأخبار...").tint(AppTheme.green).padding(.top, 80)
                    } else if let error = store.errorMessage, validNews.isEmpty {
                        errorState(error)
                    } else if let hero {
                        heroCard(hero)
                        sectionHeader
                        ForEach(remaining) { article in articleRow(article) }
                    } else {
                        emptyState
                    }
                }.padding(.bottom, 28)
            }
            .searchable(text: $query, prompt: "ابحث في الأخبار")
            .refreshable { await store.refresh() }
            .task { await store.refreshIfStale(maxAge: 180) }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var sourceStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: store.errorMessage == nil ? "checkmark.seal.fill" : "clock.arrow.circlepath")
                .foregroundStyle(store.errorMessage == nil ? AppTheme.green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.errorMessage == nil ? "المصادر متصلة" : (validNews.isEmpty ? "تعذر تحديث الأخبار" : "نعرض آخر أخبار مستلمة"))
                    .font(.caption.bold()).foregroundStyle(.white)
                if let lastUpdated = store.lastUpdated {
                    Text("آخر تحديث \(lastUpdated, style: .relative)").font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            Spacer()
            if store.isLoading { ProgressView().tint(AppTheme.green).scaleEffect(0.8) }
            else if store.errorMessage != nil {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(AppTheme.green) }
                    .buttonStyle(.plain)
            }
        }
        .padding(12).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["الكل", "الأحدث", "السعودية", "الانتقالات"], id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { filter = item }
                    } label: {
                        Text(item).font(.subheadline.bold())
                            .foregroundStyle(filter == item ? .black : .white)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(filter == item ? AppTheme.green : AppTheme.soft, in: Capsule())
                            .overlay(Capsule().stroke(filter == item ? Color.clear : AppTheme.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("آخر الأخبار").font(.title3.bold())
            Spacer()
            Text("\(filtered.count)").font(.caption.bold()).foregroundStyle(AppTheme.green)
        }.padding(.horizontal, 16).padding(.top, 2)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 42)).foregroundStyle(.orange)
            Text("تعذر جلب الأخبار").font(.headline)
            Text(message).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button { Task { await store.refresh() } } label: {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise").font(.subheadline.bold()).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 9).background(AppTheme.green, in: Capsule())
            }
        }.frame(maxWidth: .infinity).padding(24)
            .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16).padding(.top, 30)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper").font(.system(size: 44)).foregroundStyle(AppTheme.green)
            Text(hasActiveFilter ? "لا توجد أخبار مطابقة" : "لا توجد أخبار متاحة الآن").font(.headline)
            Text(hasActiveFilter ? "غيّر البحث أو التصنيف لعرض نتائج أخرى." : "اسحب الصفحة للتحديث أو جرّب مرة أخرى بعد قليل.")
                .font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            if hasActiveFilter {
                Button { query = ""; filter = "الكل" } label: {
                    Label("مسح الفلاتر", systemImage: "line.3.horizontal.decrease.circle").font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                }.buttonStyle(.plain)
            }
        }.padding(.top, 70)
    }

    private func heroCard(_ article: RealArticle) -> some View {
        Group {
            if let url = article.url {
                Link(destination: url) {
                    ZStack(alignment: .bottomLeading) {
                        EditorialArtwork(article: article).frame(height: 260)
                        LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                        VStack(alignment: .leading, spacing: 10) {
                            Spacer()
                            Text("أبرز خبر").font(.caption.bold()).foregroundStyle(.black)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(AppTheme.green, in: Capsule())
                            Text(article.title).font(.title3.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(4)
                            HStack {
                                Text(article.source.isEmpty ? "مصدر إخباري" : article.source).font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(1)
                                Spacer()
                                Text(article.date, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.72))
                            }
                        }.padding(18)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.border, lineWidth: 1))
                    .padding(.horizontal, 16)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func articleRow(_ article: RealArticle) -> some View {
        if let url = article.url {
            Link(destination: url) {
                HStack(alignment: .center, spacing: 13) {
                    EditorialArtwork(article: article).frame(width: 92, height: 76)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(3)
                        HStack(spacing: 7) {
                            Text(article.source.isEmpty ? "مصدر إخباري" : article.source).font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(1)
                            Text("•").foregroundStyle(AppTheme.muted)
                            Text(article.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border, lineWidth: 1))
                .padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }
}
