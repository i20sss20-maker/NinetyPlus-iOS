import SwiftUI

struct EnhancedTransfersView: View {
    @StateObject private var store = EditorialStore.shared
    @State private var query = ""
    @State private var selectedSource = ""
    @State private var retryID = 0
    @State private var transfermarkt: CanonicalSportsClient.TransfermarktResponse?
    @State private var transfermarktLoading = false
    @State private var transfermarktError: String?

    private var articles: [RealArticle] {
        EditorialPresentation.transferArticles(reports: store.transfers, news: store.news)
    }
    private var sources: [String] {
        Array(Set(articles.map(\.source).filter { !$0.isEmpty })).sorted()
    }
    private var filtered: [RealArticle] {
        articles.filter { (selectedSource.isEmpty || $0.source == selectedSource) && EditorialPresentation.matches($0, query: query) }
    }
    private var filtering: Bool { !EditorialPresentation.normalized(query).isEmpty || !selectedSource.isEmpty }
    private var transfermarktQuery: String {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 2 ? value : "Saudi Pro League transfers"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    TopBar(title: "أخبار الانتقالات", subtitle: "أحدث الأخبار والتقارير من مصادرها")
                    transfermarktPanel
                    sourcePicker
                    PageLoadFeedback(
                        loading: store.isLoading, hasValue: !articles.isEmpty,
                        message: store.errorMessage, updatedAt: nil
                    ) { retryID += 1 }
                    if !store.isLoading && filtered.isEmpty {
                        if filtering {
                            ContentUnavailableView {
                                Label("لا توجد أخبار مطابقة", systemImage: "magnifyingglass")
                            } description: {
                                Text("جرّب اسمًا آخر أو اعرض جميع المصادر.")
                            } actions: {
                                Button("مسح البحث والتصفية") { query = ""; selectedSource = "" }
                                    .tint(AppTheme.green)
                            }
                        } else if store.errorMessage == nil {
                            ContentUnavailableView("لا توجد أخبار انتقالات الآن", systemImage: "newspaper", description: Text("اسحب الصفحة لتحديث الأخبار."))
                        }
                    }
                    ForEach(filtered) { article in
                        if let url = EditorialPresentation.safeURL(article.url) {
                            Link(destination: url) { reportCard(article) }
                                .buttonStyle(.plain).accessibilityIdentifier("transfers.article.\(article.id)")
                        }
                    }
                    if !filtered.isEmpty {
                        Text("هذه تغطية إخبارية، وليست سجلًا للصفقات المؤكدة.")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                            .frame(maxWidth: .infinity).padding(.top, 6).padding(.horizontal, 20)
                    }
                }.padding(.bottom, 28)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .searchable(text: $query, prompt: "اسم اللاعب أو النادي أو المصدر")
            .scrollDismissesKeyboard(.interactively)
            .task(id: retryID) {
                if retryID == 0 { await store.refreshIfStale(maxAge: 300) }
                else { await store.refresh() }
            }
            .task(id: transfermarktQuery) { await loadTransfermarkt() }
            .refreshable {
                async let a: Void = store.refresh()
                async let b: Void = loadTransfermarkt(force: true)
                _ = await (a, b)
            }
        }
    }

    private var transfermarktPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.title2).foregroundStyle(AppTheme.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transfermarkt").font(.headline)
                    Text("مرجع خارجي لسوق الانتقالات").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if transfermarktLoading { ProgressView().tint(AppTheme.green) }
            }
            if let response = transfermarkt, let url = URL(string: response.searchURL) {
                Link(destination: url) {
                    HStack {
                        Label("فتح البحث في Transfermarkt", systemImage: "safari")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.up.left").foregroundStyle(AppTheme.green)
                    }
                    .padding(12).background(AppTheme.soft, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityIdentifier("transfers.transfermarkt")
                ForEach(response.items.prefix(3)) { item in
                    if let itemURL = URL(string: item.url) {
                        Link(destination: itemURL) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.caption.bold()).foregroundStyle(.white).lineLimit(2)
                                Text("Transfermarkt • مرجع مفهرس").font(.caption2).foregroundStyle(AppTheme.green)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
                Text("لا نعتبر أي خبر صفقة مؤكدة إلا إذا كان هناك إعلان رسمي من النادي أو الجهة المعنية.")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            } else if let transfermarktError {
                HStack {
                    Text(transfermarktError).font(.caption).foregroundStyle(AppTheme.muted)
                    Spacer()
                    Button("إعادة المحاولة") { Task { await loadTransfermarkt(force: true) } }
                        .font(.caption.bold()).foregroundStyle(AppTheme.green)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.border))
        .padding(.horizontal, 16)
    }

    private var sourcePicker: some View {
        HStack {
            Text(filtering ? "نتائج البحث" : "آخر الأخبار").font(.headline)
            Spacer()
            Menu {
                Button("جميع المصادر") { selectedSource = "" }
                ForEach(sources, id: \.self) { source in
                    Button(source) { selectedSource = source }
                }
            } label: {
                Label(selectedSource.isEmpty ? "جميع المصادر" : selectedSource, systemImage: "line.3.horizontal.decrease")
                    .font(.caption.bold()).foregroundStyle(AppTheme.green)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(AppTheme.soft, in: Capsule())
            }.accessibilityIdentifier("transfers.sources")
        }.padding(.horizontal, 18)
    }

    @MainActor private func loadTransfermarkt(force: Bool = false) async {
        if transfermarktLoading && !force { return }
        do {
            if !force { try await Task.sleep(for: .milliseconds(450)) }
            try Task.checkCancellation()
            transfermarktLoading = true
            transfermarktError = nil
            defer { transfermarktLoading = false }
            transfermarkt = try await CanonicalSportsClient.transfermarkt(query: transfermarktQuery)
        } catch is CancellationError {
            transfermarktLoading = false
        } catch {
            transfermarktLoading = false
            transfermarktError = "تعذر تحديث مرجع Transfermarkt الآن."
        }
    }

    private func reportCard(_ article: RealArticle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if EditorialPresentation.safeURL(article.imageURL) != nil {
                EditorialArtwork(article: article)
                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text(article.title).font(.headline).foregroundStyle(.white)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 8) {
                Text(article.source.isEmpty ? "المصدر" : article.source)
                    .font(.caption.bold()).foregroundStyle(AppTheme.green).lineLimit(2)
                Spacer(minLength: 4)
                Text(SportsCopy.published(article.date))
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
            Label("قراءة الخبر من المصدر", systemImage: "arrow.up.left.square")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.border))
        .padding(.horizontal, 16)
    }
}
