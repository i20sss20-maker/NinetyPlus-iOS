import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

struct NinetyPlusSnapshotEntry: TimelineEntry {
    let date: Date
}

struct NinetyPlusProvider: TimelineProvider {
    func placeholder(in context: Context) -> NinetyPlusSnapshotEntry { .init(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (NinetyPlusSnapshotEntry) -> Void) { completion(.init(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NinetyPlusSnapshotEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: Date())], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct NinetyPlusTodayWidget: Widget {
    let kind = "NinetyPlusTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NinetyPlusProvider()) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) { Text("90").font(.title.bold()); Text("+").font(.title.bold()).foregroundStyle(.green) }
                Text("مبارياتي اليوم").font(.headline)
                Text("افتح 90+ لمشاهدة المباريات والمتابعات").font(.caption).foregroundStyle(.secondary)
            }.containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("90+ اليوم")
        .description("وصول سريع لمبارياتك ومتابعاتك")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct NinetyPlusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NinetyPlusMatchActivityAttributes.self) { context in
            VStack(spacing: 8) {
                Text(context.attributes.league).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(context.attributes.home).lineLimit(1)
                    Spacer()
                    Text(score(context.state.homeScore, context.state.awayScore)).font(.title2.bold()).monospacedDigit()
                    Spacer()
                    Text(context.attributes.away).lineLimit(1)
                }
                Text(context.state.status).font(.caption.bold()).foregroundStyle(.green)
            }.padding(.horizontal, 4).activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.attributes.home).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.away).lineLimit(1) }
                DynamicIslandExpandedRegion(.center) { Text(score(context.state.homeScore, context.state.awayScore)).font(.title2.bold()).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.status).font(.caption).foregroundStyle(.green) }
            } compactLeading: {
                Text(context.state.homeScore.map(String.init) ?? "-").monospacedDigit()
            } compactTrailing: {
                Text(context.state.awayScore.map(String.init) ?? "-").monospacedDigit()
            } minimal: {
                Image(systemName: "soccerball")
            }
        }
    }
    private func score(_ home: Int?, _ away: Int?) -> String { "\(home.map(String.init) ?? "-") : \(away.map(String.init) ?? "-")" }
}
#endif

@main
struct NinetyPlusWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder var body: some Widget {
        NinetyPlusTodayWidget()
        if #available(iOS 16.1, *) { NinetyPlusLiveActivityWidget() }
    }
}
