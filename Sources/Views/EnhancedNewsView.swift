import SwiftUI

struct EnhancedNewsView: View {
    @StateObject private var store = EditorialStore.shared
    @State private var query = ""
    @State private var filter = "الكل"
    private var filtered: [RealArticle] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.news.filter { article in
            guard article.url != nil, !article.title.isEmpty else { return false }
            if !text.isEmpty && !article.title.localizedCaseInsensitiveContains(text) && !article.source.localizedCaseInsensitiveContains(text) { return false }
            if filter == "السعودية" { return ["السعود", "الهلال", "النصر", "الاتحاد", "روشن"].contains { article.title.contains($0) } }
            if filter == "الانتقالات" { return ["انتقال", "صفقة", "تعاقد", "ميركاتو"].contains { article.title.contains($0) } }
            return true
        }.sorted { $0.date > $1.date }
    }
    private var hero: RealArticle? { filtered.first(where: { $0.imageURL != nil }) }
    private var remaining: [RealArticle] { filtered.filter { $0.id != hero?.id } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    TopBar(title: "الأخبار", subtitle: "كرة القدم، من مصادرها")
                    SegmentBar(items: ["الكل", "السعودية", "الانتقالات"], selected: $filter)
                    if store.isLoading && store.news.isEmpty {
                        ProgressView("جارٍ جلب الأخبار…").font(.caption).tint(AppTheme.green).padding(40)
                    }
                    if let error = store.newsError {
                        PageLoadFeedback(loading: store.isLoading, hasValue: !store.news.isEmpty, message: error, updatedAt: nil) { Task { await store.refresh() } }
                    }
                    if let hero, let url = hero.url {
                        Link(destination: url) { heroCard(hero) }.buttonStyle(.plain).accessibilityIdentifier("news.featured")
                    }
                    if !remaining.isEmpty {
                        HStack { Text("الأحدث").font(.title3.bold()); Spacer(); Text("\(filtered.count) خبر").font(.caption).foregroundStyle(AppTheme.muted) }.padding(.horizontal, 20)
                    }
                    ForEach(remaining) { article in
                        if let url = article.url { Link(destination: url) { articleRow(article) }.buttonStyle(.plain) }
                    }
                    if filtered.isEmpty && !store.isLoading && store.newsError == nil {
                        ContentUnavailableView(query.isEmpty && filter == "الكل" ? "لا توجد أخبار متاحة الآن" : "لا توجد أخبار مطابقة", systemImage: "newspaper")
                        if !query.isEmpty || filter != "الكل" { Button("مسح البحث والتصنيف") { query = ""; filter = "الكل" }.tint(AppTheme.green) }
                    }
                }.padding(.vertical, 10).padding(.bottom, 28)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .searchable(text: $query, prompt: "ابحث في الأخبار")
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .task { await store.refreshIfStale(maxAge: 300) }
        }
    }
    private func heroCard(_ article: RealArticle) -> some View {
        ZStack(alignment: .bottomLeading) {
            EditorialArtwork(article: article)
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                Text(article.source).font(.caption.bold()).foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(AppTheme.green, in: Capsule())
                Text(article.title).font(.title3.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(4)
                HStack {
                    Text(article.date, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Label("قراءة الخبر", systemImage: "arrow.up.left").font(.caption.bold()).foregroundStyle(AppTheme.green)
                }
            }.padding(18)
        }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.border)).padding(.horizontal, 16)
    }
    private func articleRow(_ article: RealArticle) -> some View {
        HStack(alignment: .top, spacing: 13) {
            if article.imageURL != nil {
                EditorialArtwork(article: article).frame(width: 98, height: 88).clipShape(RoundedRectangle(cornerRadius: 13))
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(3)
                Text(article.source).font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(1)
                Text(article.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
}
