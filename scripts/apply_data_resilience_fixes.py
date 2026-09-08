"""Build 99 data resilience fixes.

Goals:
- Never let the iOS client suppress a Railway request just because one upstream
  provider is out of quota. Railway owns cache/fallback selection.
- Reuse stale in-memory fixture data if a refresh fails.
- Keep partial/stale content visible and make refresh failures less disruptive.
"""
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"data resilience patch pattern missing: {label}")
    return text.replace(old, new, 1)


client = Path("Sources/Core/APIFootballClient.swift")
s = client.read_text()

# Railway already exposes canonical/cache/ESPN fallback behavior. Blocking here
# based on upstream budget prevents the app from receiving those responses.
s = replace_once(
    s,
    '''        guard let backendURL else { throw APIFootballError.missingConfiguration }\n        guard await providerGate.allowsRequests() else { throw APIFootballError.rateLimited }\n\n        var components = URLComponents(url: backendURL.appending(path: "api/football"), resolvingAgainstBaseURL: false)!''',
    '''        guard let backendURL else { throw APIFootballError.missingConfiguration }\n\n        // Do not hard-gate requests using upstream provider quota. Railway may\n        // still satisfy the request from server cache or another data source.\n        var components = URLComponents(url: backendURL.appending(path: "api/football"), resolvingAgainstBaseURL: false)!''',
    "remove client provider hard gate",
)

s = s.replace('request.setValue("NinetyPlus/3.1 iOS", forHTTPHeaderField: "User-Agent")',
              'request.setValue("NinetyPlus/3.2 iOS", forHTTPHeaderField: "User-Agent")')
client.write_text(s)


store = Path("Sources/Core/APISportsStore.swift")
s = store.read_text()

# On an ordinary refresh failure, return stale in-memory fixtures rather than
# converting a populated page into an error-only experience.
old = '''        let fixtures = try await task.value\n        if cache.count >= 24, cache[key] == nil,\n           let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { cache[oldest] = nil }\n        cache[key] = Entry(fetchedAt: Date(), fixtures: fixtures)\n        return fixtures'''
new = '''        do {\n            let fixtures = try await task.value\n            if cache.count >= 24, cache[key] == nil,\n               let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { cache[oldest] = nil }\n            cache[key] = Entry(fetchedAt: Date(), fixtures: fixtures)\n            return fixtures\n        } catch {\n            if error is CancellationError { throw error }\n            if let stale = cache[key] { return stale.fixtures }\n            throw error\n        }'''
s = replace_once(s, old, new, "stale fixture cache fallback")
store.write_text(s)


feedback = Path("Sources/Views/PageLoadFeedback.swift")
s = feedback.read_text()
old = '''            if let message {\n                VStack(spacing: 10) {\n                    Label(hasValue ? "تعذر تحديث بعض البيانات" : "تعذر تحميل البيانات", systemImage: "exclamationmark.arrow.triangle.2.circlepath")\n                        .font(.headline)\n                        .foregroundStyle(.orange)\n                    Text(message)\n                        .font(.subheadline)\n                        .foregroundStyle(AppTheme.muted)\n                        .multilineTextAlignment(.center)\n                    if hasValue {\n                        Text("نعرض آخر بيانات متاحة في هذه الصفحة.")\n                            .font(.caption)\n                            .foregroundStyle(AppTheme.muted)\n                    }\n                    Button(action: retry) {\n                        Label("إعادة المحاولة", systemImage: "arrow.clockwise")\n                            .font(.subheadline.bold())\n                            .foregroundStyle(.black)\n                            .padding(.horizontal, 18).padding(.vertical, 11)\n                            .background(AppTheme.green, in: Capsule())\n                    }\n                    .buttonStyle(.plain)\n                    .disabled(loading)\n                }\n                .frame(maxWidth: .infinity)\n                .padding(18)\n                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))\n            }'''
new = '''            if let message {\n                if hasValue {\n                    HStack(spacing: 10) {\n                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(AppTheme.green)\n                        VStack(alignment: .leading, spacing: 2) {\n                            Text("نعرض آخر بيانات متاحة").font(.caption.bold()).foregroundStyle(.white)\n                            Text("تعذر التحديث الآن، والمحتوى الحالي ما زال متاحًا.").font(.caption2).foregroundStyle(AppTheme.muted)\n                        }\n                        Spacer(minLength: 0)\n                        Button("تحديث", action: retry).font(.caption.bold()).foregroundStyle(AppTheme.green).disabled(loading)\n                    }\n                    .padding(12)\n                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))\n                } else {\n                    VStack(spacing: 10) {\n                        Label("تعذر تحميل البيانات", systemImage: "wifi.exclamationmark")\n                            .font(.headline)\n                            .foregroundStyle(.orange)\n                        Text(friendly(message))\n                            .font(.subheadline)\n                            .foregroundStyle(AppTheme.muted)\n                            .multilineTextAlignment(.center)\n                        Button(action: retry) {\n                            Label("إعادة المحاولة", systemImage: "arrow.clockwise")\n                                .font(.subheadline.bold())\n                                .foregroundStyle(.black)\n                                .padding(.horizontal, 18).padding(.vertical, 11)\n                                .background(AppTheme.green, in: Capsule())\n                        }\n                        .buttonStyle(.plain)\n                        .disabled(loading)\n                    }\n                    .frame(maxWidth: .infinity)\n                    .padding(18)\n                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))\n                }\n            }'''
s = replace_once(s, old, new, "partial content error presentation")
helper_anchor = '''        .padding(.horizontal, 16)\n    }\n}'''
helper_new = '''        .padding(.horizontal, 16)\n    }\n\n    private func friendly(_ raw: String) -> String {\n        let text = raw.lowercased()\n        if text.contains("الحد") || text.contains("rate") || text.contains("429") {\n            return "المصدر الرئيسي مزدحم الآن. سنحاول استخدام مصدر بديل عند التحديث."\n        }\n        if text.contains("network") || text.contains("اتصال") || text.contains("الخدمة") {\n            return "تعذر الاتصال بمصادر 90+ مؤقتًا. تحقق من الإنترنت ثم أعد المحاولة."\n        }\n        return "لم نتمكن من جلب هذه الصفحة الآن. المحتوى الآخر في التطبيق يظل متاحًا."\n    }\n}'''
s = replace_once(s, helper_anchor, helper_new, "friendly page error copy")
feedback.write_text(s)

print("Build 99 data resilience fixes applied")
