import SwiftUI

struct PlayerCompareView: View {
    @State private var leftQuery = ""
    @State private var rightQuery = ""
    @State private var leftResults: [APIPlusPlayer] = []
    @State private var rightResults: [APIPlusPlayer] = []
    @State private var leftPlayer: APIPlusPlayer?
    @State private var rightPlayer: APIPlusPlayer?
    @State private var loadingLeft = false
    @State private var loadingRight = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("مقارنة اللاعبين")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                HStack(alignment: .top, spacing: 10) {
                    pickerColumn(title: "اللاعب الأول", query: $leftQuery, results: leftResults, selected: leftPlayer, loading: loadingLeft) { text in
                        await search(text: text, side: .left)
                    } onSelect: { leftPlayer = $0; leftResults = [] }

                    pickerColumn(title: "اللاعب الثاني", query: $rightQuery, results: rightResults, selected: rightPlayer, loading: loadingRight) { text in
                        await search(text: text, side: .right)
                    } onSelect: { rightPlayer = $0; rightResults = [] }
                }
                .padding(.horizontal, 16)

                if let leftPlayer, let rightPlayer {
                    comparison(left: leftPlayer, right: rightPlayer)
                } else {
                    ContentUnavailableView("اختر لاعبين للمقارنة", systemImage: "person.2.fill", description: Text("المقارنة تعرض البيانات المنشورة من المصدر فقط، بدون تقديرات أو أرقام مختلقة."))
                        .padding(.top, 30)
                }
            }
            .padding(.vertical, 12)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مقارنة")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pickerColumn(title: String, query: Binding<String>, results: [APIPlusPlayer], selected: APIPlusPlayer?, loading: Bool, onSearch: @escaping (String) async -> Void, onSelect: @escaping (APIPlusPlayer) -> Void) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.caption.bold()).foregroundStyle(AppTheme.muted)
            TextField("اسم اللاعب", text: query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { Task { await onSearch(query.wrappedValue) } }

            if loading { ProgressView().tint(AppTheme.green) }

            if let selected {
                playerMini(selected)
            } else {
                ForEach(results.prefix(5)) { player in
                    Button { onSelect(player) } label: {
                        HStack(spacing: 8) {
                            RemoteBadge(url: player.photo)
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                            Text(player.name).font(.caption.bold()).foregroundStyle(.white).lineLimit(2)
                            Spacer()
                        }
                        .padding(8)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playerMini(_ p: APIPlusPlayer) -> some View {
        VStack(spacing: 8) {
            RemoteBadge(url: p.photo)
                .frame(width: 78, height: 78)
                .clipShape(Circle())
            Text(p.name).font(.headline).multilineTextAlignment(.center).lineLimit(2)
            Text(p.nationality ?? "").font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func comparison(left: APIPlusPlayer, right: APIPlusPlayer) -> some View {
        VStack(spacing: 0) {
            compareRow(title: "الجنسية", left: left.nationality, right: right.nationality)
            compareRow(title: "تاريخ الميلاد", left: left.birth, right: right.birth)
            compareRow(title: "الطول", left: left.height, right: right.height)
            compareRow(title: "الوزن", left: left.weight, right: right.weight)
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func compareRow(title: String, left: String?, right: String?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(AppTheme.green)
            HStack(alignment: .top) {
                Text(display(left)).frame(maxWidth: .infinity, alignment: .leading)
                Divider().frame(height: 22).overlay(Color.white.opacity(0.12))
                Text(display(right)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.subheadline)
            Divider().overlay(Color.white.opacity(0.08))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @MainActor private func search(text: String, side: Side) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, APIFootballClient.isConfigured else { return }
        switch side {
        case .left: loadingLeft = true
        case .right: loadingRight = true
        }
        let result = (try? await APISportsStore.shared.searchPlayers(q)) ?? []
        switch side {
        case .left: leftResults = result; loadingLeft = false
        case .right: rightResults = result; loadingRight = false
        }
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }

    private enum Side { case left, right }
}
