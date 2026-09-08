import SwiftUI

struct EnhancedNewsView: View {
    @StateObject private var store = EditorialStore.shared
    @State private var query = ""
    @State private var filter = "الكل"
    @AppStorage("v2.savedArticleIDs") private var savedArticleIDs = ""
    @AppStorage("v2.mutedNewsSources") private var mutedNewsSources = ""

    private var saved: Set<String> { Set(savedArticleIDs.split(separator: ",").map(String.init)) }
    private var muted: Set<String> { Set(mutedNewsSources.split(separator: "|").map(String.init)) }

    private var filtered: [RealArticle] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.news.filter { article in
            guard EditorialPresentation.safeURL(article.url) != nil, !article.title.isEmpty else { return false }
            guard !muted.contains(article.source) else { return false }
            if !EditorialPresentation.matches(article, query: text) { return false }
            if filter == "السعودية" { return ["السعود", "الهلال", "النصر", "الاتحاد", "روشن", "الأهلي", "المنتخب"].contains { article.title.contains($0) } }
            if filter == "الانتقالات" { return EditorialPresentation.isTransferTopic(article.title) }
            if filter == "المحفوظة" { return saved.contains(articleKey(article)) }
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
                    SegmentBar(items: ["الكل", "السعودية", "الانتقالات", "المحفوظة"], selected: $filter)
                    if store.isLoading && store.news.isEmpty { ProgressView("جارٍ جلب الأخبار…").font(.caption).tint(AppTheme.green).padding(40) }
                    if let error = store.newsError { PageLoadFeedback(loading: store.isLoading, hasValue: !store.news.isEmpty, message: error, updatedAt: nil) { Task { await store.refresh() } } }
                    if let hero, let url = hero.url {
                        InAppWebLink(url: url) { heroCard(hero) }
                            .buttonStyle(.plain).accessibilityIdentifier("news.featured")
                            .contextMenu { newsMenu(hero) }
                    }
                    if !remaining.isEmpty {
                        HStack { Text("الأحدث").font(.title3.bold()); Spacer(); Text("\(filtered.count) خبر".englishDigits).font(.caption).foregroundStyle(AppTheme.muted).monospacedDigit() }.padding(.horizontal, 20)
                    }
                    ForEach(remaining) { article in
                        if let url = article.url {
                            InAppWebLink(url: url) { articleRow(article) }
                                .buttonStyle(.plain).contextMenu { newsMenu(article) }
                        }
                    }
                    if filtered.isEmpty && !store.isLoading && store.newsError == nil {
                        ContentUnavailableView(filter == "المحفوظة" ? "ما عندك أخبار محفوظة" : (query.isEmpty && filter == "الكل" ? "لا توجد أخبار متاحة الآن" : "لا توجد أخبار مطابقة"), systemImage: filter == "المحفوظة" ? "bookmark" : "newspaper")
                        if !query.isEmpty || filter != "الكل" { Button("مسح البحث والتصنيف") { query = ""; filter = "الكل" }.tint(AppTheme.green) }
                    }
                    if !muted.isEmpty { mutedSourcesCard }
                }.padding(.vertical, 10).padding(.bottom, 28)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .searchable(text: $query, prompt: "ابحث في الأخبار")
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .task { await store.refreshIfStale(maxAge: 300) }
        }
    }

    @ViewBuilder private func newsMenu(_ article: RealArticle) -> some View {
        Button { toggleSaved(article) } label: { Label(saved.contains(articleKey(article)) ? "إزالة من المحفوظة" : "حفظ الخبر", systemImage: saved.contains(articleKey(article)) ? "bookmark.slash" : "bookmark") }
        Button(role: .destructive) { muteSource(article.source) } label: { Label("كتم \(article.source)", systemImage: "speaker.slash") }
        if let url = article.url { ShareLink(item: url) { Label("مشاركة", systemImage: "square.and.arrow.up") } }
    }

    private var mutedSourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("المصادر المكتومة").font(.headline); Spacer(); Button("إلغاء الكل") { mutedNewsSources = "" }.font(.caption).foregroundStyle(AppTheme.green) }
            ForEach(muted.sorted(), id: \.self) { source in
                HStack { Text(source).font(.caption); Spacer(); Button { unmuteSource(source) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted) } }
            }
        }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private func heroCard(_ article: RealArticle) -> some View {
        ZStack(alignment: .bottomLeading) {
            EditorialArtwork(article: article)
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(article.source).font(.caption.bold()).foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 6).background(AppTheme.green, in: Capsule())
                    Spacer()
                    if saved.contains(articleKey(article)) { Image(systemName: "bookmark.fill").foregroundStyle(AppTheme.green) }
                }
                Text(article.title).font(.title3.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(4)
                HStack { Text(SportsCopy.published(article.date)).font(.caption2).foregroundStyle(.white.opacity(0.8)); Spacer(); Label("قراءة الخبر", systemImage: "arrow.up.left").font(.caption.bold()).foregroundStyle(AppTheme.green) }
            }.padding(18)
        }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.border)).padding(.horizontal, 16)
    }

    private func articleRow(_ article: RealArticle) -> some View {
        HStack(alignment: .top, spacing: 13) {
            if article.imageURL != nil { EditorialArtwork(article: article).frame(width: 98, height: 88).clipShape(RoundedRectangle(cornerRadius: 13)) }
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) { Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(3); if saved.contains(articleKey(article)) { Image(systemName: "bookmark.fill").foregroundStyle(AppTheme.green).font(.caption) } }
                Text(article.source).font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(1)
                Text(SportsCopy.published(article.date)).font(.caption2).foregroundStyle(AppTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }

    private func articleKey(_ article: RealArticle) -> String { String(describing: article.id).replacingOccurrences(of: ",", with: "_") }
    private func toggleSaved(_ article: RealArticle) { var values = saved; let key = articleKey(article); if values.contains(key) { values.remove(key) } else { values.insert(key) }; savedArticleIDs = values.sorted().joined(separator: ",") }
    private func muteSource(_ source: String) { var values = muted; values.insert(source); mutedNewsSources = values.sorted().joined(separator: "|") }
    private func unmuteSource(_ source: String) { var values = muted; values.remove(source); mutedNewsSources = values.sorted().joined(separator: "|") }
}
